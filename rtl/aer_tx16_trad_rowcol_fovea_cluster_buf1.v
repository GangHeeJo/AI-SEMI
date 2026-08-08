// cluster_buf의 1-deep 버전(§44 비교용) -- 소스별 pending을 0/1 한 비트만 씀.
// 2-deep(650.826um²/43.9977uW)의 비용이 예상보다 커서, "재발화 손실을 얼마나
// 포기하면 비용이 얼마나 내려가는지" 스윕의 저쪽 끝. 1-deep은 사실상 "발화 시
// pending 플래그를 세우고 grant 시 내리는" plain cluster의 req-level 모델과
// 동일한 표현력이라, 재발화 시 예전 실측(128/256)과 같은 손실이 나올 것으로 예상.
module aer_tx16_trad_rowcol_fovea_cluster_buf1 #(
  parameter WEIGHT = 5
) (
  input         clk,
  input         rst,
  input  [15:0] arrival,      // 펄스: 소스 i에 방금 새 이벤트 1개 도착(1사이클)
  output [15:0] overrun,      // 이번 사이클 도착했는데 버퍼(1개)가 이미 꽉 차서 유실된 소스
  output reg        valid,
  output reg [1:0]  row,
  output reg [3:0]  col_mask
);
  reg pending_cnt [0:15]; // 소스별 0/1개 대기중
  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  integer k;

  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = pending_cnt[gk];
      assign pending_full[gk] = pending_cnt[gk];
    end
  endgenerate
  assign overrun = arrival & pending_full;

  wire [3:0] row_req;
  assign row_req[0] = |pending_gt0[3:0];
  assign row_req[1] = |pending_gt0[7:4];
  assign row_req[2] = |pending_gt0[11:8];
  assign row_req[3] = |pending_gt0[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;

  localparam RW = (WEIGHT == 0) ? 1 : $clog2(WEIGHT + 1);
  reg [RW-1:0] round;
  wire prefer_center = (round != WEIGHT[RW-1:0]);

  wire center_avail = |(row_req & CENTER_MASK);
  wire periph_avail = |(row_req & PERIPH_MASK);
  wire use_center = (prefer_center && center_avail) || (!prefer_center && !periph_avail && center_avail);
  wire use_periph = (!prefer_center && periph_avail) || (prefer_center && !center_avail && periph_avail);

  wire [3:0] center_req_in = use_center ? (row_req & CENTER_MASK) : 4'b0000;
  wire [3:0] periph_req_in = use_periph ? (row_req & PERIPH_MASK) : 4'b0000;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  wire [3:0] row_gnt = use_center ? center_gnt : (use_periph ? periph_gnt : 4'b0000);

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_row_cols;
  always @(*) begin
    case (idx4(row_gnt))
      2'd0: sel_row_cols = pending_gt0[3:0];
      2'd1: sel_row_cols = pending_gt0[7:4];
      2'd2: sel_row_cols = pending_gt0[11:8];
      default: sel_row_cols = pending_gt0[15:12];
    endcase
  end

  wire [1:0] win_row_idx = idx4(row_gnt);
  reg [3:0] grant_mask; // 이번 사이클에 실제로 서비스(카운터 감소)될 열들
  always @(*) begin
    grant_mask = (|row_gnt) ? sel_row_cols : 4'b0000;
  end

  always @(posedge clk) begin
    if (rst) begin
      round <= {RW{1'b0}};
    end else if (|row_gnt) begin
      round <= (round == WEIGHT[RW-1:0]) ? {RW{1'b0}} : round + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid <= 1'b0; row <= 2'd0; col_mask <= 4'd0;
    end else begin
      valid <= |row_gnt;
      row <= win_row_idx;
      col_mask <= grant_mask;
    end
  end

  // 소스별 pending 플래그 갱신: 도착하면 세움(이미 꽉 찼으면 무시=overrun), 이번
  // 사이클에 그 소스가 grant_mask로 서비스됐으면 내림. 같은 사이클에 도착+서비스가
  // 겹치면(2'b11) 순증감으로 상쇄되어 그대로 1 유지(방금 도착한 걸 즉시 서비스한 것).
  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 16; k = k + 1) pending_cnt[k] <= 1'b0;
    end else begin
      for (k = 0; k < 16; k = k + 1) begin
        case ({arrival[k] && !pending_full[k], grant_mask[k % 4] && (win_row_idx == k/4)})
          2'b10: pending_cnt[k] <= 1'b1;
          2'b01: pending_cnt[k] <= 1'b0;
          2'b11: pending_cnt[k] <= 1'b1;
          default: pending_cnt[k] <= pending_cnt[k];
        endcase
      end
    end
  end
endmodule
