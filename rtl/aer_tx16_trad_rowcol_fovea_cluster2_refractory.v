// cluster2 + refractory period(생물 뉴런의 불응기 모방). 같은 소스 재발화 문제(§44)를
// "저장"(2-deep buffer, cluster_buf)이 아니라 "억제"로 접근하는 실험 -- 뉴런이 발화
// 직후 R cycle 동안 다시 발화 못 하는 것처럼, 소스가 grant된 직후 R cycle 동안 그
// 소스의 새 도착을 아예 pending으로 안 받아준다(저장 안 함, 이벤트 자체가 사라짐 --
// 손실 없는 buffer와 달리 이건 의도적/비가역적 손실).
//
// cluster_buf와 똑같이 arrival(펄스, "방금 새 이벤트 1개 도착")을 입력으로 씀. 내부에
// 소스당 pending 1비트(=cluster의 req level과 동일한 표현력)를 두는데, cluster2를
// 블랙박스 서브모듈로 감싸면 "grant 시 pending 해제"를 다른 always 블록에서 cluster2의
// 등록된 출력(valid0/row0/col_mask0)을 읽어 판단해야 해서, 같은 clk 엣지에 서로 다른
// always 블록이 넌블로킹으로 얽히는 레이스가 생김(둘 다 valid0가 "이미 갱신된 새 값"인
// 줄 알고 반응하려 하지만, 실제로는 그 엣지에서는 "엣지 이전(=한 사이클 전) 값"만
// 읽힘 -- pending 해제가 실제보다 한 사이클 늦어져서 같은 소스가 두 번 grant되는
// phantom 발생, 처음 구현에서 이 버그로 대량의 PHANTOM을 겪고 원인 확인 후 수정함).
// 그래서 cluster2의 중재 로직(center_arb/periph_arb + 열 선택)을 통째로 인라인해서
// pending 갱신과 "같은 always 블록, 같은 콤비네이셔널 신호"로 동기화함 -- cluster_buf가
// cluster를 인라인했던 것과 동일한 이유.
module aer_tx16_trad_rowcol_fovea_cluster2_refractory #(
  parameter R = 1 // 발화(grant) 직후 억제 사이클 수(R=0이면 순수 cluster2와 동일)
) (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output [15:0] suppressed,     // refractory 때문에 못 받아준 도착
  output [15:0] retrigger_drop, // refractory는 아니지만 이미 pending이라 못 받아준 도착
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  localparam RCW = (R == 0) ? 1 : $clog2(R + 1);
  reg [RCW-1:0] refractory_cnt [0:15];
  reg pending [0:15];
  wire [15:0] in_refractory;
  wire [15:0] pending_bits;
  integer k;

  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: rg
      assign in_refractory[gk] = (refractory_cnt[gk] != 0);
      assign pending_bits[gk] = pending[gk];
    end
  endgenerate

  assign suppressed     = arrival & in_refractory & ~pending_bits;
  assign retrigger_drop = arrival & pending_bits;

  // --- cluster2 중재 로직 인라인(pending_bits를 req로) ---
  wire [3:0] row_req;
  assign row_req[0] = |pending_bits[3:0];
  assign row_req[1] = |pending_bits[7:4];
  assign row_req[2] = |pending_bits[11:8];
  assign row_req[3] = |pending_bits[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_center_cols, sel_periph_cols;
  always @(*) begin
    case (idx4(center_gnt))
      2'd0: sel_center_cols = pending_bits[3:0];
      2'd1: sel_center_cols = pending_bits[7:4];
      2'd2: sel_center_cols = pending_bits[11:8];
      default: sel_center_cols = pending_bits[15:12];
    endcase
    case (idx4(periph_gnt))
      2'd0: sel_periph_cols = pending_bits[3:0];
      2'd1: sel_periph_cols = pending_bits[7:4];
      2'd2: sel_periph_cols = pending_bits[11:8];
      default: sel_periph_cols = pending_bits[15:12];
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= |center_gnt;
      row0 <= idx4(center_gnt);
      col_mask0 <= sel_center_cols;

      valid1 <= |periph_gnt;
      row1 <= idx4(periph_gnt);
      col_mask1 <= sel_periph_cols;
    end
  end

  // --- pending/refractory 갱신: 같은 사이클의 center_gnt/periph_gnt(콤비네이셔널,
  // 이번 pending_bits로 방금 계산된 값)를 그대로 써서 같은 엣지에 동기화. ---
  wire [1:0] center_row_idx = idx4(center_gnt);
  wire [1:0] periph_row_idx = idx4(periph_gnt);
  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 16; k = k + 1) begin
        refractory_cnt[k] <= {RCW{1'b0}};
        pending[k] <= 1'b0;
      end
    end else begin
      for (k = 0; k < 16; k = k + 1) begin
        if (|center_gnt && (k[3:2] == center_row_idx) && sel_center_cols[k[1:0]]) begin
          pending[k] <= 1'b0;
          refractory_cnt[k] <= R[RCW-1:0];
        end else if (|periph_gnt && (k[3:2] == periph_row_idx) && sel_periph_cols[k[1:0]]) begin
          pending[k] <= 1'b0;
          refractory_cnt[k] <= R[RCW-1:0];
        end else begin
          if (arrival[k] && !in_refractory[k] && !pending[k])
            pending[k] <= 1'b1;
          if (refractory_cnt[k] != 0)
            refractory_cnt[k] <= refractory_cnt[k] - 1'b1;
        end
      end
    end
  end
endmodule
