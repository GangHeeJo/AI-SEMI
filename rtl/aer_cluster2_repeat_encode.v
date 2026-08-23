// 주소 오버헤드 재도전(리벤지) — §74 repeat-compression을 bitmap 전환 없이 순수하게
// 재시도. 레인별로 "직전에 실제 보낸 (row,col_mask)"를 sticky 레지스터로 기억해뒀다가,
// 이번 사이클 grant가 그것과 완전히 같으면 1비트(repeat=1)만 보내고 row/col_mask
// 자체는 아예 안 보낸다. 다르면 기존 그대로(1+2+4=7비트, native와 완전히 동일 -- 손해
// 케이스가 없다). §74가 bitmap과 결합해서 전체 순손실이 났던 것과 달리, 이번엔 스위칭
// 로직(모드 판단·비교) 자체가 이것 하나(6비트 비교기)뿐이라 PPA 비용이 row-trim급으로
// 작을 것으로 기대.
module aer_cluster2_repeat_encode (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire [1:0]  row0,
  input  wire [3:0]  col_mask0,
  input  wire        valid1,
  input  wire [1:0]  row1,
  input  wire [3:0]  col_mask1,
  output wire        repeat0,     // 1이면 row0/col_mask0는 안 보내도 됨(수신측 기억으로 복원)
  output wire        repeat1,
  output wire [31:0] bits_out     // 이번 사이클 실제 전송 비트수(두 레인 합) -- 계측용
);
  // repeat0/1/bits_out은 이번 사이클의 valid0/row0/col_mask0(등록출력)를 그대로
  // 조합논리로 인코딩한 것 -- row-trim 인코더와 동일한 패턴(메모리만 순차, 판단은
  // 조합). 여기서 한 사이클 더 지연시키면 디코더 쪽 재구성 타이밍과 어긋난다.
  reg [1:0] last_row0; reg [3:0] last_cm0; reg last_row0_valid;
  reg [1:0] last_row1; reg [3:0] last_cm1; reg last_row1_valid;

  assign repeat0 = valid0 && last_row0_valid && (row0 == last_row0) && (col_mask0 == last_cm0);
  assign repeat1 = valid1 && last_row1_valid && (row1 == last_row1) && (col_mask1 == last_cm1);
  assign bits_out = (valid0 ? (repeat0 ? 32'd1 : 32'd7) : 32'd0)
                   + (valid1 ? (repeat1 ? 32'd1 : 32'd7) : 32'd0);

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
