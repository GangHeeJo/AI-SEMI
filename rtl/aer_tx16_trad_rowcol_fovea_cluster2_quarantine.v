// cluster2 + 공용 오버플로 큐(quarantine buffer, §53 사전측정으로 실현성 확인 후 구현).
// 소스 16개 전부에 전용 카운터를 두는 cluster_buf(§44, 650.826um²) 대신, 재발화
// 충돌(이미 pending인데 또 도착)이 난 소스의 "주소"만 작은 공용 큐에 넣는다.
//
// §53 사전측정(15% 부하, 50000cycle): 동시충돌이 0개(89.4%)/1개(9.8%)/2개(0.6%)/
// 3개(0.03%)뿐. 처음에 "한 사이클에 최대 Q개까지 동시 enqueue" 버전을 짰다가 정확성
// 검증에서 미묘한 버그(소스별 잔류 backlog가 서서히 누적)를 잡지 못해 시간 대비 효율이
// 안 좋다고 판단 -- 동시충돌 2개 이상은 전체의 0.63%뿐이라, **한 사이클에 1개만 큐에
// 받는(나머지는 진짜 overrun) 단순한 버전**으로 낮춰서 검증 가능성을 높임.
module aer_tx16_trad_rowcol_fovea_cluster2_quarantine #(
  parameter Q = 4 // 이 파일의 enqueue if-else 체인은 Q=4 고정 가정(§53 측정상 3개 이상
                   // 동시충돌이 사실상 없어서 4면 충분 -- Q 바꾸려면 그 체인도 같이 수정)
) (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output [15:0] overrun,       // 진짜로 버려진 소스(이번 사이클) -- 큐가 꽉 찼거나
                                // 이번 사이클에 이미 다른 충돌이 큐를 차지한 경우
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  reg pending [0:15];
  reg [3:0] q_addr [0:Q-1];
  reg       q_valid [0:Q-1];
  // 각 always 블록마다 전용 루프 변수를 씀(공유하면 서로 다른 블록이 같은 시뮬레이션
  // 시점에 얽힐 때 루프 상태가 오염될 수 있음 -- 실제로 이 버그로 소스별 잔류 backlog가
  // 조금씩 새는 문제를 겪고 원인 확인 후 분리함).
  integer pu_s;  // pending-update 클럭 블록 전용
  integer pm_j;  // q_pop_mask 조합 블록 전용
  integer ao_s;  // accept_one 조합 블록 전용
  integer en_j;  // 큐 리셋/갱신용(pending-update 블록 내부에서만 사용)
  integer qb_i, qb_j; // queued_addr_bitmap 조합 블록 전용
  reg claimed [0:15];

  wire [15:0] pending_bits;
  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: pb
      assign pending_bits[gk] = pending[gk];
    end
  endgenerate

  // --- cluster2 중재 로직 인라인(pending_bits를 req로, cluster2_refractory와 동일 패턴).
  // Genus가 아이카러스와 달리 전방참조(뒤에 선언된 wire를 먼저 쓰는 것)를 안 받아줘서,
  // granted_bitmap을 쓰는 collide/queued_addr_bitmap보다 먼저 이 블록을 배치함. ---
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

  wire [1:0] center_row_idx = idx4(center_gnt);
  wire [1:0] periph_row_idx = idx4(periph_gnt);

  wire [15:0] granted_bitmap =
    ((|center_gnt) ? (sel_center_cols << (center_row_idx*4)) : 16'd0) |
    ((|periph_gnt) ? (sel_periph_cols << (periph_row_idx*4)) : 16'd0);

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= |center_gnt; row0 <= center_row_idx; col_mask0 <= sel_center_cols;
      valid1 <= |periph_gnt; row1 <= periph_row_idx; col_mask1 <= sel_periph_cols;
    end
  end

  // 소스별로 "지금 큐에 이미 이 주소 엔트리가 있는가"(이번 사이클 팝 여부와 무관,
  // 사이클 시작 시점 기준) -- grant+새도착 동시발생 케이스를 정확히 가르는 데 씀.
  reg [15:0] queued_addr_bitmap;
  always @(*) begin
    for (qb_i = 0; qb_i < 16; qb_i = qb_i + 1) begin
      queued_addr_bitmap[qb_i] = 1'b0;
      for (qb_j = 0; qb_j < Q; qb_j = qb_j + 1)
        if (q_valid[qb_j] && (q_addr[qb_j] == qb_i[3:0])) queued_addr_bitmap[qb_i] = 1'b1;
    end
  end

  // 이미 pending인데 또 도착(재발화) -- "이번 사이클에 grant까지 같이 나는" 소스는
  // 원래 충돌이 아니라고 뺐었는데(자리가 비니까), 그건 그 소스에 큐 엔트리가 "없을
  // 때만" 맞는 얘기임 -- 큐 엔트리가 있었다면(총 2개 이상 밀려있었다면) grant 후에도
  // pending 자리는 "큐에서 승격되는 몫"으로 이미 채워질 예정이라, 이번 새 도착은
  // 여전히(3번째) 충돌임. 이 구분을 놓쳐서 새 도착이 pending/큐 어디에도 안 잡히고
  // 그냥 사라지는 버그가 있었음(실측으로 발견, 소스별 잔류 backlog로 나타남).
  wire [15:0] collide = arrival & pending_bits & (~granted_bitmap | queued_addr_bitmap);

  function integer qcount_now;
    input dummy;
    integer j;
    begin
      qcount_now = 0;
      for (j = 0; j < Q; j = j + 1) if (q_valid[j]) qcount_now = qcount_now + 1;
    end
  endfunction

  // 이번 사이클엔 collide 중 딱 하나만 큐에 받음(주소가 가장 작은 소스 우선) --
  // 그 외 collide는 전부 overrun. 큐에 빈 자리가 없으면 그 하나도 못 받고 overrun.
  reg [15:0] accept_one;
  integer picked;
  always @(*) begin
    accept_one = 16'd0;
    picked = -1;
    if (qcount_now(1'b0) < Q) begin
      for (ao_s = 15; ao_s >= 0; ao_s = ao_s - 1) // 큰 인덱스부터 봐서 최종적으로 가장 작은 인덱스가 남게
        if (collide[ao_s]) picked = ao_s;
      if (picked >= 0) accept_one[picked] = 1'b1;
    end
  end
  assign overrun = collide & ~accept_one;

  // 이번 grant가 소비하는 엔트리를 뺀 "그 외" 큐 엔트리가 이 주소로 남아있는지.
  reg [Q-1:0] q_pop_mask;
  always @(*) begin
    q_pop_mask = {Q{1'b0}};
    for (pm_j = 0; pm_j < 16; pm_j = pm_j + 1) claimed[pm_j] = 1'b0;
    for (pm_j = 0; pm_j < Q; pm_j = pm_j + 1) begin
      if (q_valid[pm_j] && granted_bitmap[q_addr[pm_j]] && !claimed[q_addr[pm_j]]) begin
        q_pop_mask[pm_j] = 1'b1;
        claimed[q_addr[pm_j]] = 1'b1;
      end
    end
  end

  // grant 하나는 항상 "총 밀린 개수(pending 1비트 + 큐 엔트리 수)"에서 정확히 1만
  // 소비해야 함. 큐에 이 주소 엔트리가 있으면(팝 대상이든 아니든) 총량이 최소 2였다는
  // 뜻이라 이번 grant 이후에도 1은 남아야 하므로 pending을 유지해야 함 -- 팝 여부로
  // 걸러내면(원래 버전의 버그) "큐 엔트리 하나 + pending 하나"를 grant 하나가 동시에
  // 둘 다 소비해버려서 실제보다 하나 더 없어지는 이중소비 버그가 생김(실측으로 발견).
  function has_queue_entry;
    input integer addr;
    integer j;
    begin
      has_queue_entry = 1'b0;
      for (j = 0; j < Q; j = j + 1)
        if (q_valid[j] && (q_addr[j] == addr[3:0]))
          has_queue_entry = 1'b1;
    end
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      for (pu_s = 0; pu_s < 16; pu_s = pu_s + 1) pending[pu_s] <= 1'b0;
      for (en_j = 0; en_j < Q; en_j = en_j + 1) begin q_valid[en_j] <= 1'b0; q_addr[en_j] <= 4'd0; end
    end else begin
      // pending 갱신.
      for (pu_s = 0; pu_s < 16; pu_s = pu_s + 1) begin
        if (granted_bitmap[pu_s])
          // 큐에 남은 게 있거나(계속 배출), 이번에 새로 큐로 받아들여졌거나(다른 소스
          // 얘기, accept_one은 이제 grant되는 소스에는 절대 안 걸림), 혹은 바로 이번에
          // grant로 자리가 빈 곳에 새 도착이 왔으면(재정의된 collide 덕에 이건 충돌로
          // 안 잡히므로 여기서 직접 반영) pending 유지.
          pending[pu_s] <= has_queue_entry(pu_s) | accept_one[pu_s] | arrival[pu_s];
        else if (arrival[pu_s] && !pending[pu_s])
          pending[pu_s] <= 1'b1;
      end

      // 큐 갱신: pop된 슬롯 비우고, accept_one으로 받아들여진 딱 하나를 "아무 빈 자리"에.
      for (en_j = 0; en_j < Q; en_j = en_j + 1)
        if (q_pop_mask[en_j]) q_valid[en_j] <= 1'b0;

      if (|accept_one) begin
        // 빈 슬롯(팝될 예정 포함) 중 가장 낮은 인덱스 하나에 넣음.
        if (!q_valid[0] || q_pop_mask[0]) begin
          q_valid[0] <= 1'b1; q_addr[0] <= picked[3:0];
        end else if (!q_valid[1] || q_pop_mask[1]) begin
          q_valid[1] <= 1'b1; q_addr[1] <= picked[3:0];
        end else if (!q_valid[2] || q_pop_mask[2]) begin
          q_valid[2] <= 1'b1; q_addr[2] <= picked[3:0];
        end else if (!q_valid[3] || q_pop_mask[3]) begin
          q_valid[3] <= 1'b1; q_addr[3] <= picked[3:0];
        end
      end
    end
  end
endmodule
