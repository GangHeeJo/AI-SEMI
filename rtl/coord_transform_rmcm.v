// Digital 2차 1단계 좌표변환 -- RMCM(Reconfigurable Multiple Constant Multiplication) 취지를
// 우리 문제 규모에 맞게 끝까지 밀어붙인 버전. xc2/yc2가 애초에 4가지 값뿐이고 theta_idx도
// 256가지뿐이라 전체 입력공간(4x4x256=4096)을 통째로 미리 계산해서 표 하나로 담아버림 --
// 곱셈기도 덧셈기도 전혀 없이 순수 룩업(디코드 트리)만 남음. coord_transform_rotate2d.v(직접
// 행렬곱), coord_transform_cordic.v(6단 unroll)와 포트/계약 동일, PPA 3자 비교용.
// 표 생성: scripts/coord_transform_model.py의 export_full_lut_verilog() (baseline transform()의
// 정확한 값을 그대로 담으므로 CORDIC과 달리 근사오차가 전혀 없음).
module coord_transform_rmcm #(
  parameter integer N_THETA_BITS = 8,
  parameter integer COORD_BITS   = 6
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
  `include "rtl/coord_transform_rmcm_lut.vh"

  // xc2/yc2(4가지 값만 나옴)를 row/col(0~3)로 되돌리는 것도 곱셈/덧셈 없이 순수 비교-선택.
  reg [1:0] row, col;
  always @(*) begin
    case (yc2_in)
      -4'sd3:  row = 2'd0;
      -4'sd1:  row = 2'd1;
       4'sd1:  row = 2'd2;
      default: row = 2'd3; // 4'sd3
    endcase
    case (xc2_in)
      -4'sd3:  col = 2'd0;
      -4'sd1:  col = 2'd1;
       4'sd1:  col = 2'd2;
      default: col = 2'd3; // 4'sd3
    endcase
  end

  wire [11:0] xy = coord_transform_rmcm_lut(row, col, theta_idx);

  always @(posedge clk) begin
    if (rst) begin
      valid_out <= 1'b0;
      x_out <= {COORD_BITS{1'b0}};
      y_out <= {COORD_BITS{1'b0}};
    end else begin
      valid_out <= valid_in;
      x_out <= xy[11:6];
      y_out <= xy[5:0];
    end
  end
endmodule
