// cluster + 소스별 최소 버퍼(2-deep pending counter). "다른 소스끼리 경합"은 cluster가
// 이미 고쳤지만, "같은 소스가 서비스되기 전에 또 발화"하는 문제(§43, elephant_mouse/
// retrigger에서 fovea·cluster·cluster2 전부 128~370건대 overrun 겪음)는 안 고쳐져
// 있었음 -- 이게 원인이 "저장공간이 아예 없어서"라, 소스마다 "몇 개 밀려있는지"만
// 세는 2-deep 포화 카운터를 추가한다. 우리는 payload가 없어서(이벤트끼리 구분 불가)
// 진짜 FIFO(값 저장)가 필요 없고, 개수만 세면 충분하다 -- 현수의 tx_fifo2보다 훨씬
// 가벼운 구조.
//
// 인터페이스가 req(레벨, "대기중")에서 arrival(펄스, "방금 새 이벤트 1개 도착")로
// 바뀜 -- 레벨 방식은 "이벤트 하나가 안 끝나서 계속 켜져있는 것"과 "이벤트가 여러
// 번 발생한 것"을 구분 못 해서(§43 rate-coding 실험에서 겪은 것과 같은 종류의 모호함)
// 애초에 버퍼링을 표현할 수 없었음. 펄스 방식이 실제 스파이크(순간적 사건)에도 더
// 충실함.
module aer_tx16_trad_rowcol_fovea_cluster_buf #(
  parameter WEIGHT = 5
) (
  input         clk,
  input         rst,
  input  [15:0] arrival,      // 펄스: 소스 i에 방금 새 이벤트 1개 도착(1사이클)
  output [15:0] overrun,      // 이번 사이클 도착했는데 버퍼(2개)가 이미 꽉 차서 유실된 소스
  output reg        valid,
  output reg [1:0]  row,
  output reg [3:0]  col_mask
);
  reg [1:0] pending_cnt [0:15]; // 소스별 0~2개 대기중
  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  integer k;

  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = (pending_cnt[gk] != 2'd0);
      assign pending_full[gk] = (pending_cnt[gk] == 2'd2);
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

  // 소스별 pending 카운터 갱신: 도착하면 +1(꽉 찼으면 무시=overrun), 이번 사이클에
  // 그 소스가 grant_mask로 서비스됐으면 -1. 같은 사이클에 도착+서비스가 겹치면
  // 순증감(+1-1=0)으로 자연스럽게 처리됨.
  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 16; k = k + 1) pending_cnt[k] <= 2'd0;
    end else begin
      for (k = 0; k < 16; k = k + 1) begin
        case ({arrival[k] && !pending_full[k], grant_mask[k % 4] && (win_row_idx == k/4)})
          2'b10: pending_cnt[k] <= pending_cnt[k] + 2'd1;
          2'b01: pending_cnt[k] <= pending_cnt[k] - 2'd1;
          2'b11: pending_cnt[k] <= pending_cnt[k]; // +1-1 상쇄
          default: pending_cnt[k] <= pending_cnt[k];
        endcase
      end
    end
  end
endmodule
