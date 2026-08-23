// cluster2 + 현수의 Dir7(주소 중복 억제, UniSpike arXiv 2605.23796 착안) 결합.
// 현수의 aer_cluster2_redundancy.sv(~/semi-ai/rtl/)와 동일한 아이디어를 우리 repo에
// 재구현 -- 순수 wrapper라 cluster2 코어는 무수정으로 그대로 감싸기만 함.
//
// 아이디어: 같은 레인에서 바로 직전 사이클과 (row, col_mask)가 완전히 동일하면
// (실제 DVS 트래픽에서 "같은 위치가 연속 재발화"하는 흔한 패턴), 버스를 다시
// 구동하지 않고 그대로 유지 -- 다운스트림은 repeat 플래그만 보고 "지난 값 재사용"
// 하면 됨. row/col_mask 버스 자체가 안 토글하므로 그 배선의 스위칭 전력이 실제로
// 줄어듦(정직한 전제: Genus/Innovus vectorless 리포트는 이 이득을 못 잡음, VCD 활동도
// 실측으로만 확인 가능 -- §60의 결합판 vectorless 오차 사례와 같은 이유).
module aer_tx16_trad_rowcol_fovea_cluster2_redundancy (
  input         clk,
  input         rst,
  input  [15:0] req,
  output        valid0,
  output [1:0]  row0,
  output [3:0]  col_mask0,
  output        repeat0,
  output        valid1,
  output [1:0]  row1,
  output [3:0]  col_mask1,
  output        repeat1
);
  wire raw_valid0, raw_valid1;
  wire [1:0] raw_row0, raw_row1;
  wire [3:0] raw_col_mask0, raw_col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 core(
    .clk(clk), .rst(rst), .req(req),
    .valid0(raw_valid0), .row0(raw_row0), .col_mask0(raw_col_mask0),
    .valid1(raw_valid1), .row1(raw_row1), .col_mask1(raw_col_mask1));

  reg last_valid0_q, last_valid1_q;
  reg [1:0] last_row0_q, last_row1_q;
  reg [3:0] last_col_mask0_q, last_col_mask1_q;

  wire same0 = raw_valid0 && last_valid0_q && (raw_row0 == last_row0_q) && (raw_col_mask0 == last_col_mask0_q);
  wire same1 = raw_valid1 && last_valid1_q && (raw_row1 == last_row1_q) && (raw_col_mask1 == last_col_mask1_q);

  reg        valid0_r, valid1_r;
  reg [1:0]  row0_r, row1_r;
  reg [3:0]  col_mask0_r, col_mask1_r;
  reg        repeat0_r, repeat1_r;

  always @(posedge clk) begin
    if (rst) begin
      valid0_r <= 1'b0; row0_r <= 2'd0; col_mask0_r <= 4'd0; repeat0_r <= 1'b0;
      valid1_r <= 1'b0; row1_r <= 2'd0; col_mask1_r <= 4'd0; repeat1_r <= 1'b0;
      last_valid0_q <= 1'b0; last_row0_q <= 2'd0; last_col_mask0_q <= 4'd0;
      last_valid1_q <= 1'b0; last_row1_q <= 2'd0; last_col_mask1_q <= 4'd0;
    end else begin
      valid0_r  <= raw_valid0;
      repeat0_r <= same0;
      if (!same0) begin
        row0_r      <= raw_row0;
        col_mask0_r <= raw_col_mask0;
      end // else: row0/col_mask0 버스 유지, 재구동 안 함

      valid1_r  <= raw_valid1;
      repeat1_r <= same1;
      if (!same1) begin
        row1_r      <= raw_row1;
        col_mask1_r <= raw_col_mask1;
      end

      last_valid0_q    <= raw_valid0;
      last_row0_q      <= raw_row0;
      last_col_mask0_q <= raw_col_mask0;
      last_valid1_q    <= raw_valid1;
      last_row1_q      <= raw_row1;
      last_col_mask1_q <= raw_col_mask1;
    end
  end

  assign valid0 = valid0_r; assign row0 = row0_r; assign col_mask0 = col_mask0_r; assign repeat0 = repeat0_r;
  assign valid1 = valid1_r; assign row1 = row1_r; assign col_mask1 = col_mask1_r; assign repeat1 = repeat1_r;
endmodule
