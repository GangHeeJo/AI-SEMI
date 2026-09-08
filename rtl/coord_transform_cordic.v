// Digital 2차 1단계 좌표변환 -- CORDIC(회전모드) 버전. coord_transform_rotate2d.v(직접 행렬곱
// baseline)와 포트/계약은 완전히 같고 내부 계산 방식만 다름. 곱셈기(가변 x 가변) 없이
// shift+add만으로 회전을 구현 -- 유일한 곱셈은 게인보정(가변 x 고정상수, 상수곱이라 합성 시
// shift+add 네트워크로 최적화 가능, RMCM과 같은 원리).
//
// 소프트웨어 오라클: scripts/coord_transform_cordic_model.py. 대수적 단순화(선형성 이용):
//   world = (Wc,Hc) + Rot(theta)*(R,0) + Rot(theta)*(xc,yc) = (Wc,Hc) + Rot(theta)*(xc+R,yc)
// 로 두 항을 한 번에 회전 -- baseline이 안 쓴 단순화라 곱셈 자체도 원래보다 줄어듦.
// N_ITER=6은 4x4x256 전수 스윕으로 찾은 최소값(<=1칸 오차, 5회는 80/4096 실패 -- 오라클 참고).
module coord_transform_cordic #(
  parameter integer N_THETA_BITS = 8,
  parameter integer COORD_BITS   = 6,
  parameter integer R  = 20,
  parameter integer WC = 32,
  parameter integer HC = 32
)(
  input                        clk,
  input                        rst,
  input                        valid_in,
  input  signed [3:0]          xc2_in,
  input  signed [3:0]          yc2_in,
  input  [N_THETA_BITS-1:0]    theta_idx,
  output reg                   valid_out,
  output reg [COORD_BITS-1:0]  x_out,
  output reg [COORD_BITS-1:0]  y_out
);
  localparam integer FRAC_BITS = 14;
  // atan(2^-i)*2^14, i=0..5 (scripts/coord_transform_cordic_model.py ATAN_TABLE와 동일)
  localparam signed [15:0] ATAN0 = 16'sd12868;
  localparam signed [15:0] ATAN1 = 16'sd7596;
  localparam signed [15:0] ATAN2 = 16'sd4014;
  localparam signed [15:0] ATAN3 = 16'sd2037;
  localparam signed [15:0] ATAN4 = 16'sd1023;
  localparam signed [15:0] ATAN5 = 16'sd512;
  localparam signed [15:0] INV_K_FX = 16'sd9951; // (1/CORDIC게인)*2^14, N_ITER=6 기준 상수

  `include "rtl/coord_transform_cordic_z0_lut.vh"

  // 象限 折疊: 상위 2bit로 90도 단위 사전회전(swap/negate만, 곱셈기 불필요),
  // 하위 6bit(0~63, 0~약88.6도)만 CORDIC 반복 대상 -- 항상 수렴범위(<99.7도) 안.
  wire [1:0] quadrant = theta_idx[N_THETA_BITS-1:N_THETA_BITS-2];
  wire [5:0] residual = theta_idx[5:0];

  // xc2/yc2는 2배 스케일(xc2=2*xc) -- R도 2배로 맞춰 미리 더해서 한 번만 회전(선형성 이용).
  wire signed [7:0] x0 = xc2_in + 2*R;
  wire signed [7:0] y0 = yc2_in;

  reg signed [7:0] qx, qy;
  always @(*) begin
    case (quadrant)
      2'd0: begin qx = x0;  qy = y0;  end
      2'd1: begin qx = -y0; qy = x0;  end
      2'd2: begin qx = -x0; qy = -y0; end
      default: begin qx = y0; qy = -x0; end
    endcase
  end

  wire signed [15:0] z_init = coord_transform_cordic_z0_lut({2'b00, residual});

  // 게인보정 -- 유일한 곱셈(가변 x 고정상수), 합성기가 shift+add로 최적화 가능.
  wire signed [23:0] x_s0 = qx * INV_K_FX;
  wire signed [23:0] y_s0 = qy * INV_K_FX;
  wire signed [15:0] z_s0 = z_init;

  // CORDIC 반복 6단, 전개(unroll) -- 매 단 shift+add(부호에 따라 가감)만 사용.
  wire dir0 = z_s0[15];   // 1=음수(반대방향 회전)
  wire signed [23:0] x_s1 = dir0 ? (x_s0 + (y_s0 >>> 0)) : (x_s0 - (y_s0 >>> 0));
  wire signed [23:0] y_s1 = dir0 ? (y_s0 - (x_s0 >>> 0)) : (y_s0 + (x_s0 >>> 0));
  wire signed [15:0] z_s1 = dir0 ? (z_s0 + ATAN0) : (z_s0 - ATAN0);

  wire dir1 = z_s1[15];
  wire signed [23:0] x_s2 = dir1 ? (x_s1 + (y_s1 >>> 1)) : (x_s1 - (y_s1 >>> 1));
  wire signed [23:0] y_s2 = dir1 ? (y_s1 - (x_s1 >>> 1)) : (y_s1 + (x_s1 >>> 1));
  wire signed [15:0] z_s2 = dir1 ? (z_s1 + ATAN1) : (z_s1 - ATAN1);

  wire dir2 = z_s2[15];
  wire signed [23:0] x_s3 = dir2 ? (x_s2 + (y_s2 >>> 2)) : (x_s2 - (y_s2 >>> 2));
  wire signed [23:0] y_s3 = dir2 ? (y_s2 - (x_s2 >>> 2)) : (y_s2 + (x_s2 >>> 2));
  wire signed [15:0] z_s3 = dir2 ? (z_s2 + ATAN2) : (z_s2 - ATAN2);

  wire dir3 = z_s3[15];
  wire signed [23:0] x_s4 = dir3 ? (x_s3 + (y_s3 >>> 3)) : (x_s3 - (y_s3 >>> 3));
  wire signed [23:0] y_s4 = dir3 ? (y_s3 - (x_s3 >>> 3)) : (y_s3 + (x_s3 >>> 3));
  wire signed [15:0] z_s4 = dir3 ? (z_s3 + ATAN3) : (z_s3 - ATAN3);

  wire dir4 = z_s4[15];
  wire signed [23:0] x_s5 = dir4 ? (x_s4 + (y_s4 >>> 4)) : (x_s4 - (y_s4 >>> 4));
  wire signed [23:0] y_s5 = dir4 ? (y_s4 - (x_s4 >>> 4)) : (y_s4 + (x_s4 >>> 4));
  wire signed [15:0] z_s5 = dir4 ? (z_s4 + ATAN4) : (z_s4 - ATAN4);

  wire dir5 = z_s5[15];
  wire signed [23:0] x_s6 = dir5 ? (x_s5 + (y_s5 >>> 5)) : (x_s5 - (y_s5 >>> 5));
  wire signed [23:0] y_s6 = dir5 ? (y_s5 - (x_s5 >>> 5)) : (y_s5 + (x_s5 >>> 5));
  // z_s6는 더 안 씀(마지막 방향 결정까지만 필요)

  // x_s6 = 2*SCALE*[Rot(theta)*(xc+R,yc)]_x (xc2가 2배 스케일이라 SCALE 한 번만 더 나누면 됨)
  localparam integer DENOM = 2 * (1 << FRAC_BITS); // 2*2^14 = 2^15
  localparam integer HALF  = DENOM / 2;

  function automatic signed [23:0] round_div_pow2(input signed [23:0] n);
    reg signed [23:0] mag;
    begin
      if (n >= 0) mag = (n + HALF) >>> (FRAC_BITS + 1);
      else        mag = (-n + HALF) >>> (FRAC_BITS + 1);
      round_div_pow2 = (n >= 0) ? mag : -mag;
    end
  endfunction

  wire signed [23:0] dx = round_div_pow2(x_s6);
  wire signed [23:0] dy = round_div_pow2(y_s6);
  wire signed [23:0] x_full = WC + dx;
  wire signed [23:0] y_full = HC + dy;

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
