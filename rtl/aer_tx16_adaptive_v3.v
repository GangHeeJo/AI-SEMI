// Adaptive Foveated AER v3 — v2(활동량=arrival rate, STD와 유사한 "빠른 크기 감쇠")에
// IOR의 DS(direct suppression, "지연된 강제 억제") 성분을 추가한 버전.
//
// 문헌 근거(참고논문.md 섹션 6, Satel et al. 2013 arXiv:1307.5684 원문 정독):
// 인간의 Inhibition of Return은 STD(조기 감각 순응, 새 입력의 크기를 서서히 줄임)와
// DS(direct suppression, 자극 후 약 600ms 뒤부터 시작되는 별도의 지연된 억제)의 두 성분이
// 합쳐진 현상이며, 논문에서 둘 중 하나만으로는 실제 행동 데이터를 재현 못 하고 반드시
// 둘 다 있어야 함을 직접 검증함. v2의 activity 감쇠(decay_cnt/DECAY_SHIFT)가 이미 STD 역할을
// 하고 있으므로, 여기서는 DS 역할 — "아무리 활동량이 높아도(=hot으로 계속 뽑혀도) 최근에
// 이미 많이 서비스받았으면 일정 시간 강제로 cold 취급" — 을 추가한다.
//
// 주의: 생물학적 IOR/habituation의 원래 목적은 "이미 본 곳을 그만 보고 새 곳을 탐색"
// (foraging/visual search 효율화)으로, 우리 FAER의 목적("바쁜 곳=물체 위치를 계속
// 우선시해서 추적")과 정반대다. 그래서 그대로 베끼지 않고, 목적을 "최악지연(worst-case
// latency) 개선"으로 재정의해서 적용한다 — hot 행이 계속 이겨서 cold 행이 가끔 심하게
// 밀리는 기존 트레이드오프(progress.md 5-9)에 대한 anti-starvation 장치로 사용.
//
// 파라미터:
//   SERVICE_LIMIT — 한 행이 (감쇠 없이) 연속으로 이만큼 서비스받으면 강제 냉각 시작.
//   COOLDOWN_LEN  — 강제로 cold 취급되는 기간(사이클).
// v2와 동일한 파라미터 제약(DECAY_SHIFT>=2, activity 오버플로우 상한 등)도 그대로 적용됨.
module aer_tx16_adaptive_v3 #(
  parameter WEIGHT = 3,
  parameter DECAY_SHIFT = 6,
  parameter SERVICE_LIMIT = 8,
  parameter COOLDOWN_LEN = 16
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  input  [15:0] new_event,
  output reg    valid,
  output reg    addr_type,
  output reg [1:0] addr
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  wire [2:0] row_new_cnt [0:3];
  assign row_new_cnt[0] = new_event[0]+new_event[1]+new_event[2]+new_event[3];
  assign row_new_cnt[1] = new_event[4]+new_event[5]+new_event[6]+new_event[7];
  assign row_new_cnt[2] = new_event[8]+new_event[9]+new_event[10]+new_event[11];
  assign row_new_cnt[3] = new_event[12]+new_event[13]+new_event[14]+new_event[15];

  reg [15:0] activity [0:3];
  reg [DECAY_SHIFT-1:0] decay_cnt;
  wire decay_tick = (decay_cnt == {DECAY_SHIFT{1'b1}});

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

  wire [3:0] rank_hot_mask;
  assign rank_hot_mask[0] = (rank0 < 2);
  assign rank_hot_mask[1] = (rank1 < 2);
  assign rank_hot_mask[2] = (rank2 < 2);
  assign rank_hot_mask[3] = (rank3 < 2);

  // --- DS(direct suppression): 연속 서비스 카운터 + 강제 냉각 타이머 ---
  reg [7:0] serve_cnt [0:3];
  reg [7:0] cooldown  [0:3];
  wire [3:0] forced_cold;
  genvar gk;
  generate
    for (gk = 0; gk < 4; gk = gk + 1) begin: fc
      assign forced_cold[gk] = (cooldown[gk] != 8'd0);
    end
  endgenerate

  wire [3:0] hot_mask = rank_hot_mask & ~forced_cold;
  wire [3:0] cold_mask = ~hot_mask;

  reg [15:0] round;
  wire prefer_hot = (round != WEIGHT[15:0]);

  reg state;

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
      for (k = 0; k < 4; k = k + 1) begin
        activity[k] <= 16'd0;
        serve_cnt[k] <= 8'd0;
        cooldown[k] <= 8'd0;
      end
    end else begin
      tie_rotor <= tie_rotor + 2'd1;
      decay_cnt <= decay_cnt + 1'b1;
      for (k = 0; k < 4; k = k + 1) begin
        if (decay_tick)
          activity[k] <= (activity[k] >> 1) + {13'd0, row_new_cnt[k]};
        else
          activity[k] <= activity[k] + {13'd0, row_new_cnt[k]};

        // 냉각 타이머는 매 사이클 감소; 0이 되면 다시 rank 기준 분류로 복귀.
        if (cooldown[k] != 8'd0)
          cooldown[k] <= cooldown[k] - 8'd1;

        // 이 행이 이번에 뽑히지 않았으면 serve_cnt도 activity처럼 서서히 식는다
        // (STD와 같은 감쇠 주기 사용 — "최근에" 계속 이긴 경우만 카운트).
        if (row_gnt[k]) begin
          if (serve_cnt[k] == SERVICE_LIMIT[7:0] - 8'd1) begin
            serve_cnt[k] <= 8'd0;
            cooldown[k] <= COOLDOWN_LEN[7:0];
          end else begin
            serve_cnt[k] <= serve_cnt[k] + 8'd1;
          end
        end else if (decay_tick && serve_cnt[k] != 8'd0) begin
          serve_cnt[k] <= serve_cnt[k] - 8'd1;
        end
      end

      case (state)
        1'b0: begin
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0;
            addr <= idx4(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[15:0]) ? 16'd0 : round + 16'd1;
          end else begin
            valid <= 1'b0;
          end
        end
        1'b1: begin
          if (col_bitmap != 4'd0) begin
            valid <= 1'b1;
            addr_type <= 1'b1;
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
