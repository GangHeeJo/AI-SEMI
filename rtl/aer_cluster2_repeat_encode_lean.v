// aer_cluster2_repeat_encode의 실제 제품용 버전 -- bits_out(32비트 계측용 출력, 테스트
// 벤치의 비트비용 집계 전용이라 실제 하드웨어엔 필요 없음)을 빼고 repeat0/1만 낸다.
// 순수 PPA 측정을 위해 분리(§88 첫 합성이 이 계측 로직 때문에 면적이 부풀려짐을 발견).
module aer_cluster2_repeat_encode_lean (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire [1:0]  row0,
  input  wire [3:0]  col_mask0,
  input  wire        valid1,
  input  wire [1:0]  row1,
  input  wire [3:0]  col_mask1,
  output wire        repeat0,
  output wire        repeat1
);
  reg [1:0] last_row0; reg [3:0] last_cm0; reg last_row0_valid;
  reg [1:0] last_row1; reg [3:0] last_cm1; reg last_row1_valid;

  assign repeat0 = valid0 && last_row0_valid && (row0 == last_row0) && (col_mask0 == last_cm0);
  assign repeat1 = valid1 && last_row1_valid && (row1 == last_row1) && (col_mask1 == last_cm1);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      last_row0 <= 2'd0; last_cm0 <= 4'd0; last_row0_valid <= 1'b0;
      last_row1 <= 2'd0; last_cm1 <= 4'd0; last_row1_valid <= 1'b0;
    end else begin
      if (valid0) begin last_row0 <= row0; last_cm0 <= col_mask0; last_row0_valid <= 1'b1; end
      if (valid1) begin last_row1 <= row1; last_cm1 <= col_mask1; last_row1_valid <= 1'b1; end
    end
  end
endmodule
