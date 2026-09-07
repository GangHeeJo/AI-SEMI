// Digital 2차 1단계 좌표변환 -- 로컬 4x4 좌표(xc2,yc2, 2배 스케일 정수) + theta_idx(0~255)
// -> 64x64 world memory 좌표(x_out,y_out). 소프트웨어 오라클(scripts/coord_transform_model.py)의
// transform()과 정수 고정소수점 산술을 한 비트도 안 틀리게 그대로 재현한다 -- 이 파일이 만드는
// 값이 틀리면 오라클이 아니라 이 RTL이 틀린 것.
//
// 통합 회전 모델: world(X,Y) = round(offset(theta) + Rot(theta)*(xc,yc) + (WC,HC))
// cos(theta)/sin(theta) LUT 하나를 offset과 local 회전 양쪽에 재사용(회로 관점에서 공짜).
// 직접 행렬곱(곱셈기 사용) baseline -- CORDIC/RMCM 비교는 이 baseline의 PPA 실측 이후 후속.
module coord_transform_rotate2d #(
  parameter integer N_THETA_BITS = 8,   // theta LUT 인덱스 비트 수 (2^8=256단계)
  parameter integer COORD_BITS   = 6,   // world 좌표 비트 수 (64x64)
  parameter integer R  = 20,            // 시야중심 원호 반지름 (grid cell)
  parameter integer WC = 32,            // world grid 중심 X
  parameter integer HC = 32             // world grid 중심 Y
)(
  input                        clk,
  input                        rst,
  input                        valid_in,
  input  signed [3:0]          xc2_in,   // 2*col-3, col 0~3 -> -3,-1,1,3
  input  signed [3:0]          yc2_in,   // 2*row-3, row 0~3 -> -3,-1,1,3
  input  [N_THETA_BITS-1:0]    theta_idx,
  output reg                   valid_out,
  output reg [COORD_BITS-1:0]  x_out,
  output reg [COORD_BITS-1:0]  y_out
);
  localparam integer FRAC_BITS = 14;          // cos/sin Q1.14
  localparam integer SCALE     = 1 << FRAC_BITS;
  localparam integer DENOM     = 2 * SCALE;   // 32768 = 2^15, 나눗셈 shift량과 동일
  localparam integer HALF      = DENOM / 2;

  // cos/sin ROM -- scripts/coord_transform_model.py의 export_lut_hex()가 만든 파일 그대로 로드.
  reg signed [15:0] cos_rom [0:(1<<N_THETA_BITS)-1];
  reg signed [15:0] sin_rom [0:(1<<N_THETA_BITS)-1];
  initial begin
    $readmemh("rtl/coord_transform_cos_q1_14.hex", cos_rom);
    $readmemh("rtl/coord_transform_sin_q1_14.hex", sin_rom);
  end

  wire signed [15:0] c = cos_rom[theta_idx];
  wire signed [15:0] s = sin_rom[theta_idx];

  // 폭 근거: xc2/yc2 최대 3, c/s 최대 16384 -> 곱 최대 49152, local_rot 합 최대 ~98304(18bit면 충분).
  // offset=2*(R*c) 최대 ~655360(21bit), 중심(2*SCALE*WC) 최대 1048576(22bit) -- 전부 더해도
  // 24bit signed(최대 ~838만) 안에 넉넉히 들어옴.
  wire signed [23:0] local_rot_x = xc2_in * c - yc2_in * s;
  wire signed [23:0] local_rot_y = xc2_in * s + yc2_in * c;
  wire signed [23:0] offset_x    = 2 * (R * c);
  wire signed [23:0] offset_y    = 2 * (R * s);
  localparam signed [23:0] CENTER_X = 2 * SCALE * WC;
  localparam signed [23:0] CENTER_Y = 2 * SCALE * HC;

  // WC/HC를 반올림 *이전에* 전부 더해서 "절대좌표" 하나로 만든 뒤 딱 한 번만 반올림한다.
  // (오프셋만 따로 반올림하면 오프셋이 음수일 때 반올림 방향이 뒤집히는 버그 -- 오라클에서
  // 이미 한 번 겪고 고친 것과 동일한 이유, scripts/coord_transform_model.py 주석 참고.)
  wire signed [23:0] total_x = local_rot_x + offset_x + CENTER_X;
  wire signed [23:0] total_y = local_rot_y + offset_y + CENTER_Y;

  // denom(2^15)이 항상 2의 거듭제곱이므로, 0에서 먼 방향으로 반올림하는 나눗셈을
  // "부호 분리 -> 절대값에 HALF 더해서 shift -> 부호 복원"으로 곱셈기 없이 구현.
  function automatic signed [23:0] round_div_pow2(input signed [23:0] n);
    reg signed [23:0] mag;
    begin
      if (n >= 0) mag = (n + HALF) >>> (FRAC_BITS + 1);
      else        mag = (-n + HALF) >>> (FRAC_BITS + 1);
      round_div_pow2 = (n >= 0) ? mag : -mag;
    end
  endfunction

  wire signed [23:0] x_full = round_div_pow2(total_x);
  wire signed [23:0] y_full = round_div_pow2(total_y);

  always @(posedge clk) begin
    if (rst) begin
      valid_out <= 1'b0;
      x_out <= {COORD_BITS{1'b0}};
      y_out <= {COORD_BITS{1'b0}};
    end else begin
      valid_out <= valid_in;
      x_out <= x_full[COORD_BITS-1:0];
      y_out <= y_full[COORD_BITS-1:0];
    end
  end
endmodule
