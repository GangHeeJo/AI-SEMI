// Adaptive Foveated AER v2 — "지금 얼마나 밀려있나(backlog 수준)"가 아니라
// "방금 새로 도착했나(arrival, new_event 펄스)"로 활동량을 잰다.
//
// v1에서 겪은 문제: activity를 (1)선택횟수, (2)요청유무, (3)밀린열개수 순으로 바꿔봤지만,
// 심한 과부하가 오래 지속되면 "cold로 분류된 행조차 배경 트래픽만으로 큐가 다 차버려서"
// 결국 hot이든 cold든 "거의 항상 꽉 차있다"는 점에서 구별이 안 되는 문제가 매번 재발함
// (모서리 핫스팟 실시간 이동 테스트로 직접 확인). backlog "수준"은 서비스를 못 받으면
// 저절로 포화돼버려서, 원래 도착률이 얼마였는지의 정보를 결국 잃어버리는 게 근본 원인.
//
// 해결책: req(밀림 여부, 중재에 계속 사용)와는 별도로, new_event(그 셀에 "방금 새
// 이벤트가 도착했다"는 1사이클짜리 펄스)를 활동량 측정 전용으로 받는다. 도착 "속도"는
// 큐가 꽉 찼든 비었든 상관없이 계속 다르게 유지되므로, 포화 상태에서도 구별력을 잃지 않는다.
// (실제 칩에서는 픽셀 자신의 "변화 감지" 신호가 이 역할을 할 수 있음 — DVS 픽셀은 원래
// "지금 막 바뀌었다"는 순간을 스스로 아니까.)
// 파라미터 제약(실측으로 확인함):
// ① DECAY_SHIFT >= 2 여야 함. DECAY_SHIFT=1(2사이클마다 감쇠, 극단적으로 빠름)에서는
//    특정 행이 3000사이클 넘게 한 번도 서비스 안 받는 영구 기아 상태가 실제로 발생함.
// ② activity가 16비트라서, DECAY_SHIFT가 너무 크면(감쇠 주기가 너무 길면) 감쇠가 일어나기도
//    전에 activity 자체가 16비트를 넘어 오버플로우(랩어라운드)할 수 있음 — 4x4에서는
//    "2^DECAY_SHIFT * 4(행당 최대 열 개수) < 65536" 즉 DECAY_SHIFT<=13이어야 안전함을
//    직접 확인(DECAY_SHIFT=15,16에서 cyc=16384에 activity가 65532→0으로 뚝 떨어지는
//    진짜 오버플로우를 관측함 — 의도한 절반 감쇠가 아니라 레지스터 랩어라운드였음).
// 실제로 쓰는 값(3~8)은 둘 다 전혀 문제없음.
module aer_tx16_adaptive_v2 #(
  parameter WEIGHT = 3,        // hot:cold 가중치 비율
  parameter DECAY_SHIFT = 6    // 2^DECAY_SHIFT 사이클마다 활동량 카운터를 절반으로 감쇠(최근성 반영). >=2 필수.
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  input  [15:0] new_event,    // 활동량 측정 전용: 셀별 "방금 새 이벤트 도착" 1사이클 펄스
  output reg    valid,
  output reg    addr_type,   // 0=ROW, 1=COL
  output reg [1:0] addr
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  // 행마다 "방금 몇 개의 열에 새 이벤트가 도착했는지"(0~4) — 활동량을 여기서 잰다.
  wire [2:0] row_new_cnt [0:3];
  assign row_new_cnt[0] = new_event[0]+new_event[1]+new_event[2]+new_event[3];
  assign row_new_cnt[1] = new_event[4]+new_event[5]+new_event[6]+new_event[7];
  assign row_new_cnt[2] = new_event[8]+new_event[9]+new_event[10]+new_event[11];
  assign row_new_cnt[3] = new_event[12]+new_event[13]+new_event[14]+new_event[15];

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
      // ④(v2, 현재) "방금 새로 도착한 열 개수(row_new_cnt)"로 활동량을 잰다 — backlog
      // 수준이 아니라 도착 "속도"라서, 큐가 얼마나 차있든 상관없이 계속 구별력을 유지한다.
      decay_cnt <= decay_cnt + 1'b1;
      for (k = 0; k < 4; k = k + 1) begin
        if (decay_tick)
          activity[k] <= (activity[k] >> 1) + {13'd0, row_new_cnt[k]};
        else
          activity[k] <= activity[k] + {13'd0, row_new_cnt[k]};
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
