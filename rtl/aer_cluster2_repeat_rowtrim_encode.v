// row-trim(§86)+repeat-flag(§88) 결합 — 서로 다른 종류의 중복을 동시에 겨냥.
// row-trim은 순정 cluster2에서만 안전(§87: steal이 이 전제를 깨서 steal_buf엔 못 씀)이라
// 이 결합판도 순정 cluster2 전용. 레인당: repeat=1이면 1비트만(row-trim도 필요없음,
// row/col_mask 자체를 안 보내므로), repeat=0이면 1(repeat flag)+1(row_bit, trim)+4(col_mask)
// =6비트(원래 7비트에서 1비트 추가 절감).
module aer_cluster2_repeat_rowtrim_encode (
  input  wire        clk,
  input  wire        rst,
  input  wire        valid0,
  input  wire [1:0]  row0,      // 순정 cluster2 전제: 항상 2'd1 또는 2'd2
  input  wire [3:0]  col_mask0,
  input  wire        valid1,
  input  wire [1:0]  row1,      // 순정 cluster2 전제: 항상 2'd0 또는 2'd3
  input  wire [3:0]  col_mask1,
  output wire        repeat0,
  output wire        repeat1,
  output wire        row0_bit,  // repeat0=0일 때만 유효: 0=row1, 1=row2
  output wire        row1_bit,  // repeat1=0일 때만 유효: 0=row0, 1=row3
  output wire [31:0] bits_out   // 계측용(테스트벤치 전용, 합성 시 자동으로 최적화됨 -- §88에서 확인됨)
);
  reg [1:0] last_row0; reg [3:0] last_cm0; reg last_row0_valid;
  reg [1:0] last_row1; reg [3:0] last_cm1; reg last_row1_valid;

  assign repeat0 = valid0 && last_row0_valid && (row0 == last_row0) && (col_mask0 == last_cm0);
  assign repeat1 = valid1 && last_row1_valid && (row1 == last_row1) && (col_mask1 == last_cm1);
  assign row0_bit = (row0 == 2'd2);
  assign row1_bit = (row1 == 2'd3);
  assign bits_out = (valid0 ? (repeat0 ? 32'd1 : 32'd6) : 32'd0)
                   + (valid1 ? (repeat1 ? 32'd1 : 32'd6) : 32'd0);

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
