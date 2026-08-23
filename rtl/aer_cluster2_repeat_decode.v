// aer_cluster2_repeat_encode의 짝 디코더. repeat0/1=1이면 row/col_mask는 실제로
// 링크에 실리지 않는다는 전제로, 그 입력을 아예 무시하고 자기 자신의 sticky 메모리로만
// 복원한다(테스트벤치에서 repeat 사이클엔 row/col_mask 입력을 일부러 0으로 지워서
// 이 전제를 검증함).
module aer_cluster2_repeat_decode (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire        repeat0,
  input  wire [1:0]  row0_in,      // repeat0=0일 때만 유효(실제 링크에서도 이때만 전송)
  input  wire [3:0]  col_mask0_in,
  input  wire        valid1,
  input  wire        repeat1,
  input  wire [1:0]  row1_in,
  input  wire [3:0]  col_mask1_in,
  output reg  [1:0]  row0_out,
  output reg  [3:0]  col_mask0_out,
  output reg  [1:0]  row1_out,
  output reg  [3:0]  col_mask1_out
);
  reg [1:0] mem_row0; reg [3:0] mem_cm0;
  reg [1:0] mem_row1; reg [3:0] mem_cm1;

  always @(*) begin
    if (valid0) begin
      row0_out = repeat0 ? mem_row0 : row0_in;
      col_mask0_out = repeat0 ? mem_cm0 : col_mask0_in;
    end else begin
      row0_out = 2'd0; col_mask0_out = 4'd0;
    end
    if (valid1) begin
      row1_out = repeat1 ? mem_row1 : row1_in;
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
      if (valid0 && !repeat0) begin mem_row0 <= row0_in; mem_cm0 <= col_mask0_in; end
      if (valid1 && !repeat1) begin mem_row1 <= row1_in; mem_cm1 <= col_mask1_in; end
    end
  end
endmodule
