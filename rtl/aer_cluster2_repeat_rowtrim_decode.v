// aer_cluster2_repeat_rowtrim_encode의 짝 디코더. repeat0/1=1이면 row0_bit/col_mask
// 입력 자체가 실제로는 전송 안 됨(테스트벤치가 그 경우 0으로 지워서 검증) -- 자기
// sticky 메모리(원본 row/col_mask 그대로 기억)로 복원.
module aer_cluster2_repeat_rowtrim_decode (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire        repeat0,
  input  wire        row0_bit_in,   // repeat0=0일 때만 유효
  input  wire [3:0]  col_mask0_in,
  input  wire        valid1,
  input  wire        repeat1,
  input  wire        row1_bit_in,
  input  wire [3:0]  col_mask1_in,
  output reg  [1:0]  row0_out,
  output reg  [3:0]  col_mask0_out,
  output reg  [1:0]  row1_out,
  output reg  [3:0]  col_mask1_out
);
  reg [1:0] mem_row0; reg [3:0] mem_cm0;
  reg [1:0] mem_row1; reg [3:0] mem_cm1;
  wire [1:0] new_row0 = row0_bit_in ? 2'd2 : 2'd1;
  wire [1:0] new_row1 = row1_bit_in ? 2'd3 : 2'd0;

  always @(*) begin
    if (valid0) begin
      row0_out = repeat0 ? mem_row0 : new_row0;
      col_mask0_out = repeat0 ? mem_cm0 : col_mask0_in;
    end else begin
      row0_out = 2'd0; col_mask0_out = 4'd0;
    end
    if (valid1) begin
      row1_out = repeat1 ? mem_row1 : new_row1;
      col_mask1_out = repeat1 ? mem_cm1 : col_mask1_in;
    end else begin
      row1_out = 2'd0; col_mask1_out = 4'd0;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      mem_row0 <= 2'd0; mem_cm0 <= 4'd0;
      mem_row1 <= 2'd0; mem_cm1 <= 4'd0;
    end else begin
      if (valid0 && !repeat0) begin mem_row0 <= new_row0; mem_cm0 <= col_mask0_in; end
      if (valid1 && !repeat1) begin mem_row1 <= new_row1; mem_cm1 <= col_mask1_in; end
    end
  end
endmodule
