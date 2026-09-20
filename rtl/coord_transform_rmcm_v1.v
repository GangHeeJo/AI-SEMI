// §134에서 coord_transform_rmcm.v(범용 모듈)와 그 LUT을 predictor 신규 타겟 크기(1024단계/
// 1024x1024)로 키우면서, 이미 검증된 1단계 파이프라인(aer_tx16_coord_transform_v1/v2)까지
// 같이 흔들지 않으려고 옛 크기(256단계/64x64) 스냅샷을 별도 파일로 얼려둔 것 -- 내용은
// coord_transform_rmcm.v의 §133 시점과 동일, LUT 파일/함수 이름만 charset 충돌 피하려고
// `_v1` 접미사. 패치 확장 등으로 1단계 자체를 다시 손볼 때 이 파일은 지우고 coord_transform_rmcm
// 최신판으로 옮기면 됨.
module coord_transform_rmcm_v1 (
  input                        clk,
  input                        rst,
  input                        valid_in,
  input  signed [3:0]          xc2_in,
  input  signed [3:0]          yc2_in,
  input  [7:0]                 theta_idx,
  output reg                   valid_out,
  output reg [5:0]              x_out,
  output reg [5:0]              y_out
);
  `include "rtl/coord_transform_rmcm_lut_v1.vh"

  reg [1:0] row, col;
  always @(*) begin
    case (yc2_in)
      -4'sd3:  row = 2'd0;
      -4'sd1:  row = 2'd1;
       4'sd1:  row = 2'd2;
      default: row = 2'd3;
    endcase
    case (xc2_in)
      -4'sd3:  col = 2'd0;
      -4'sd1:  col = 2'd1;
       4'sd1:  col = 2'd2;
      default: col = 2'd3;
    endcase
  end

  wire [11:0] xy = coord_transform_rmcm_lut_v1(row, col, theta_idx);

  always @(posedge clk) begin
    if (rst) begin
      valid_out <= 1'b0;
      x_out <= 6'd0;
      y_out <= 6'd0;
    end else begin
      valid_out <= valid_in;
      x_out <= xy[11:6];
      y_out <= xy[5:0];
    end
  end
endmodule
