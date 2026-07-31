// Adaptive Foveated AER (A-FAER) — 고정된 "중심" 대신, 각 행(row)의 "최근 활동량"을
// 추적해서 지금 제일 바쁜 2개 행("hot")에 동적으로 우선권(WEIGHT:1)을 준다.
// FAER(aer_tx16_fovea.v)이 "중심에 중요한 게 있을 것"이라는 고정된 베팅을 하는 반면,
// 이 설계는 "실제로 이벤트가 많이 몰리는 곳"을 스스로 따라간다 — 물체가 어디로 움직이든
// 그 물체가 있는 쪽에 우선권이 자동으로 이동하는지 확인하기 위한 실험.
module aer_tx16_adaptive #(
  parameter WEIGHT = 3,        // hot:cold 가중치 비율
  parameter DECAY_SHIFT = 6    // 2^DECAY_SHIFT 사이클마다 활동량 카운터를 절반으로 감쇠(최근성 반영)
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg    valid,
  output reg    addr_type,   // 0=ROW, 1=COL
  output reg [1:0] addr
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  // 행마다 "몇 개의 열이 동시에 밀려있는지"(0~4) — 활동량을 여기서 잰다.
  // (row_req 1비트만 쓰면, 배경까지 다 밀려서 4개 행 전부 row_req=1이 되는 심한 과부하
  //  상황에서 서로 구별이 아예 안 되는 문제를 실제로 겪음 — 몇 개나 밀렸는지를 보면
  //  전부 "뭔가는 밀려있는" 상태여도 여전히 구별 가능함.)
  wire [2:0] row_pending_cnt [0:3];
  assign row_pending_cnt[0] = req[0]+req[1]+req[2]+req[3];
  assign row_pending_cnt[1] = req[4]+req[5]+req[6]+req[7];
  assign row_pending_cnt[2] = req[8]+req[9]+req[10]+req[11];
  assign row_pending_cnt[3] = req[12]+req[13]+req[14]+req[15];

  // --- 행별 "최근 활동량" 카운터 (선택될 때마다 +1, 주기적으로 절반 감쇠) ---
  reg [15:0] activity [0:3];
  reg [DECAY_SHIFT-1:0] decay_cnt;
  wire decay_tick = (decay_cnt == {DECAY_SHIFT{1'b1}});

  // --- 활동량 기준으로 hot(상위 2개)/cold(하위 2개) 순위 매기기 ---
  // rank[i] = i보다 활동량이 많은(또는 동점이면 회전 포인터 기준 더 가까운) 행의 개수. rank 0,1 = hot.
  //
  // 주의(실제 겪은 버그): 처음엔 동점일 때 "인덱스가 작은 쪽"을 항상 우대하도록 짰었는데,
  // 모서리 핫스팟 실험(row0,row3가 대칭적으로 똑같이 바빠야 하는 상황)에서 row0이 row3보다
  // 24%나 더 많이 선택되는 걸 발견함 — tie-break 방향을 반대로 뒤집어봤더니 정확히 반대로
  // (row3가 24% 더 많이 선택) 뒤집혀서, "동점 시 인덱스 고정 우대"가 원인임을 직접 확인함.
  // 어느 한쪽을 고정 우대하는 대신, 매 사이클 회전하는 포인터(tie_rotor) 기준 "누가 더
  // 가까운지"로 동점을 처리해서 특정 인덱스가 항상 유리해지는 일이 없게 함.
  reg [1:0] tie_rotor;

  function [1:0] circ_dist;
    input integer idx;
    input [1:0] rotor;
    circ_dist = idx[1:0] - rotor;
  endfunction

  function is_greater(input [15:0] a_val, input integer a_idx, input [15:0] b_val, input integer b_idx, input [1:0] rotor);
    is_greater = (b_val > a_val) || (b_val == a_val && circ_dist(b_idx,rotor) < circ_dist(a_idx,rotor));
  endfunction

  wire [1:0] rank0 = (is_greater(activity[0],0,activity[1],1,tie_rotor)?1:0) + (is_greater(activity[0],0,activity[2],2,tie_rotor)?1:0) + (is_greater(activity[0],0,activity[3],3,tie_rotor)?1:0);
  wire [1:0] rank1 = (is_greater(activity[1],1,activity[0],0,tie_rotor)?1:0) + (is_greater(activity[1],1,activity[2],2,tie_rotor)?1:0) + (is_greater(activity[1],1,activity[3],3,tie_rotor)?1:0);
  wire [1:0] rank2 = (is_greater(activity[2],2,activity[0],0,tie_rotor)?1:0) + (is_greater(activity[2],2,activity[1],1,tie_rotor)?1:0) + (is_greater(activity[2],2,activity[3],3,tie_rotor)?1:0);
  wire [1:0] rank3 = (is_greater(activity[3],3,activity[0],0,tie_rotor)?1:0) + (is_greater(activity[3],3,activity[1],1,tie_rotor)?1:0) + (is_greater(activity[3],3,activity[2],2,tie_rotor)?1:0);

  wire [3:0] hot_mask;
  assign hot_mask[0] = (rank0 < 2);
  assign hot_mask[1] = (rank1 < 2);
  assign hot_mask[2] = (rank2 < 2);
  assign hot_mask[3] = (rank3 < 2);
  wire [3:0] cold_mask = ~hot_mask;

  reg [15:0] round;
  wire prefer_hot = (round != WEIGHT[15:0]);

  reg state; // 0=IDLE, 1=BURST

  wire hot_avail  = |(row_req & hot_mask);
  wire cold_avail = |(row_req & cold_mask);
  wire use_hot  = (state == 1'b0) && ((prefer_hot && hot_avail) || (!prefer_hot && !cold_avail && hot_avail));
  wire use_cold = (state == 1'b0) && ((!prefer_hot && cold_avail) || (prefer_hot && !hot_avail && cold_avail));

  wire [3:0] hot_req_in  = use_hot  ? (row_req & hot_mask)  : 4'b0000;
  wire [3:0] cold_req_in = use_cold ? (row_req & cold_mask) : 4'b0000;
  wire [3:0] hot_gnt, cold_gnt;

  arbiter4 hot_arb (.clk(clk), .rst(rst), .req(hot_req_in),  .gnt(hot_gnt));
  arbiter4 cold_arb(.clk(clk), .rst(rst), .req(cold_req_in), .gnt(cold_gnt));

  wire [3:0] row_gnt = use_hot ? hot_gnt : (use_cold ? cold_gnt : 4'b0000);
  reg [3:0] col_bitmap;

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
      2'd0: sel_row_cols = req[3:0];
      2'd1: sel_row_cols = req[7:4];
      2'd2: sel_row_cols = req[11:8];
      default: sel_row_cols = req[15:12];
    endcase
  end

  wire [3:0] col_bitmap_next = col_bitmap & (col_bitmap - 4'd1);
  integer k;

  always @(posedge clk) begin
    if (rst) begin
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 2'd0; col_bitmap <= 4'd0; round <= 16'd0;
      decay_cnt <= {DECAY_SHIFT{1'b0}};
      tie_rotor <= 2'd0;
      for (k = 0; k < 4; k = k + 1) activity[k] <= 16'd0;
    end else begin
      tie_rotor <= tie_rotor + 2'd1; // 동점 처리 기준점을 매 사이클 돌려서 특정 행이 항상 유리해지지 않게 함
      // 활동량 갱신 이력:
      // ① "선택될 때마다 +1" → 정책이 만든 결과를 다시 원인으로 써서 자기강화적 악순환 발생(버그).
      // ② "요청 유무(row_req, 1비트)로 +0/+1" → 배경 트래픽까지 큐가 다 차서 4개 행 전부
      //    row_req=1이 되는 심한 과부하 상황에서, 전부 매 사이클 똑같이 +1씩만 늘어나
      //    영원히 동점이 되어 구별이 아예 안 되는 문제 발견(모서리 핫스팟 실시간 이동 테스트에서
      //    activity=[116,116,116,116]처럼 완전히 같아지는 걸 실측으로 확인).
      // ③(현재) "그 행에 몇 개의 열이 동시에 밀려있는지(row_pending_cnt, 0~4)"로 세기 —
      //    전부 "뭔가는 밀려있는" 상태여도 몇 개나 밀렸는지는 계속 다르므로, 심한 과부하에서도
      //    구별력을 유지한다.
      decay_cnt <= decay_cnt + 1'b1;
      for (k = 0; k < 4; k = k + 1) begin
        if (decay_tick)
          activity[k] <= (activity[k] >> 1) + {13'd0, row_pending_cnt[k]};
        else
          activity[k] <= activity[k] + {13'd0, row_pending_cnt[k]};
      end

      case (state)
        1'b0: begin // IDLE: 행 중재
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0; // ROW
            addr <= idx4(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[15:0]) ? 16'd0 : round + 16'd1;
          end else begin
            valid <= 1'b0;
          end
        end
        1'b1: begin // BURST: 열 순차 전송
          if (col_bitmap != 4'd0) begin
            valid <= 1'b1;
            addr_type <= 1'b1; // COL
            addr <= idx4(col_bitmap);
            col_bitmap <= col_bitmap_next;
            if (col_bitmap_next == 4'd0) state <= 1'b0;
          end else begin
            valid <= 1'b0;
            state <= 1'b0;
          end
        end
      endcase
    end
  end
endmodule
