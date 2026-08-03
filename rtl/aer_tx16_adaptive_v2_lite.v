// Adaptive Foveated AER v2 "lite" — aer_tx16_adaptive_v2.v와 알고리즘은 완전히 동일하고,
// activity/round 레지스터와 순위비교기의 비트폭만 실제 사용 범위에 맞게 줄인 버전.
// 목적: adaptive v2의 PPA 손해(+688% area 등)가 "hot/cold 이중 arbiter 구조" 자체의
// 비용인지, 아니면 그냥 16비트로 안 다듬고 뒀던 비트폭 낭비였는지를 합성으로 확인.
//
// 폭 축소 근거:
//  - activity: v2에서 16비트로 뒀던 이유는 DECAY_SHIFT<=13까지 오버플로우 없이 지원하려던
//    안전마진이었음(실측: DECAY_SHIFT=15,16에서 16비트가 실제로 오버플로우함). 실사용
//    범위(DECAY_SHIFT 3~8)에서는 ACT_WIDTH=DECAY_SHIFT+3이면 2배 이상 여유롭게 안전함.
//  - round: WEIGHT(1~20 범위에서 스윕해본 값)와 비교하는 용도라 5비트(0~31)면 충분한데
//    16비트를 썼음 — 12비트를 그냥 버리고 있었던 것.
//  - 순위비교(is_greater)는 activity를 직접 비교하므로 ACT_WIDTH를 줄이면 비교기도 같이
//    줄어듦(12번 호출되는 크기비교기라 여기 효과가 제일 클 것으로 예상).
// 파라미터 제약(원본과 동일): DECAY_SHIFT >= 2 필수(영구기아 방지). ACT_WIDTH는
// DECAY_SHIFT+3으로 자동 계산되므로 별도 오버플로우 걱정 없음(원본의 ①②번 제약을
// 비트폭을 실제 필요치에 맞춤으로써 아예 해소).
module aer_tx16_adaptive_v2_lite #(
  parameter WEIGHT = 3,
  parameter DECAY_SHIFT = 6
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  input  [15:0] new_event,
  output reg    valid,
  output reg    addr_type,
  output reg [1:0] addr
);
  localparam ACT_WIDTH = DECAY_SHIFT + 3; // 2^DECAY_SHIFT * 4 < 2^ACT_WIDTH, 2배 이상 여유
  localparam RW = 5; // round/WEIGHT 비교용 — WEIGHT<=31 가정(실험 범위 0~20 커버)

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

  reg [ACT_WIDTH-1:0] activity [0:3];
  reg [DECAY_SHIFT-1:0] decay_cnt;
  wire decay_tick = (decay_cnt == {DECAY_SHIFT{1'b1}});

  reg [1:0] tie_rotor;

  function [1:0] circ_dist;
    input integer idx;
    input [1:0] rotor;
    circ_dist = idx[1:0] - rotor;
  endfunction

  function is_greater(input [ACT_WIDTH-1:0] a_val, input integer a_idx, input [ACT_WIDTH-1:0] b_val, input integer b_idx, input [1:0] rotor);
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

  reg [RW-1:0] round;
  wire prefer_hot = (round != WEIGHT[RW-1:0]);

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
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 2'd0; col_bitmap <= 4'd0; round <= {RW{1'b0}};
      decay_cnt <= {DECAY_SHIFT{1'b0}};
      tie_rotor <= 2'd0;
      for (k = 0; k < 4; k = k + 1) activity[k] <= {ACT_WIDTH{1'b0}};
    end else begin
      tie_rotor <= tie_rotor + 2'd1;
      decay_cnt <= decay_cnt + 1'b1;
      for (k = 0; k < 4; k = k + 1) begin
        if (decay_tick)
          activity[k] <= (activity[k] >> 1) + row_new_cnt[k];
        else
          activity[k] <= activity[k] + row_new_cnt[k];
      end

      case (state)
        1'b0: begin
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0;
            addr <= idx4(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[RW-1:0]) ? {RW{1'b0}} : round + 1'b1;
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
