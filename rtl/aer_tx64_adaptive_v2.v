// Adaptive Foveated AER v2 — 8x8(64셀)로 확장한 버전. 아이디어와 버그 수정 이력은
// aer_tx16_adaptive_v2.v와 동일(활동량을 backlog 수준이 아니라 new_event 도착 펄스로 측정,
// tie_rotor로 동점 편향 제거). 규모만 8행/8열로 일반화.
// 파라미터 제약(16셀 버전에서 실측 확인, 여기도 동일 적용):
// ① DECAY_SHIFT >= 2 (아주 빠른 감쇠에서 영구 기아 발생 가능).
// ② activity(16비트) 오버플로우 방지: 행당 열이 8개라 "2^DECAY_SHIFT * 8 < 65536" 즉
//    DECAY_SHIFT <= 12이어야 안전(16셀 버전보다 열이 2배라 안전 상한이 1 낮음). 실사용값(3~8)은 안전.
module aer_tx64_adaptive_v2 #(
  parameter WEIGHT = 3,
  parameter DECAY_SHIFT = 6
) (
  input         clk,
  input         rst,
  input  [63:0] req,
  input  [63:0] new_event,
  output reg    valid,
  output reg    addr_type,
  output reg [2:0] addr
);
  wire [7:0] row_req;
  genvar gr;
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin: rowreq
      assign row_req[gr] = |req[gr*8+7 : gr*8];
    end
  endgenerate

  wire [3:0] row_new_cnt [0:7];
  generate
    for (gr = 0; gr < 8; gr = gr + 1) begin: newcnt
      assign row_new_cnt[gr] = new_event[gr*8+0]+new_event[gr*8+1]+new_event[gr*8+2]+new_event[gr*8+3]
                              +new_event[gr*8+4]+new_event[gr*8+5]+new_event[gr*8+6]+new_event[gr*8+7];
    end
  endgenerate

  reg [15:0] activity [0:7];
  reg [DECAY_SHIFT-1:0] decay_cnt;
  wire decay_tick = (decay_cnt == {DECAY_SHIFT{1'b1}});

  reg [2:0] tie_rotor;

  function [2:0] circ_dist;
    input integer idx;
    input [2:0] rotor;
    circ_dist = idx[2:0] - rotor;
  endfunction

  function is_greater(input [15:0] a_val, input integer a_idx, input [15:0] b_val, input integer b_idx, input [2:0] rotor);
    is_greater = (b_val > a_val) || (b_val == a_val && circ_dist(b_idx,rotor) < circ_dist(a_idx,rotor));
  endfunction

  wire [2:0] rank [0:7];
  genvar gi, gj;
  generate
    for (gi = 0; gi < 8; gi = gi + 1) begin: rankgen
      wire [2:0] partial [0:7];
      for (gj = 0; gj < 8; gj = gj + 1) begin: rankterm
        if (gi == gj) begin
          assign partial[gj] = 3'd0;
        end else begin
          assign partial[gj] = is_greater(activity[gi],gi,activity[gj],gj,tie_rotor) ? 3'd1 : 3'd0;
        end
      end
      assign rank[gi] = partial[0]+partial[1]+partial[2]+partial[3]+partial[4]+partial[5]+partial[6]+partial[7];
    end
  endgenerate

  wire [7:0] hot_mask;
  generate
    for (gi = 0; gi < 8; gi = gi + 1) begin: hotgen
      assign hot_mask[gi] = (rank[gi] < 4);
    end
  endgenerate
  wire [7:0] cold_mask = ~hot_mask;

  reg [15:0] round;
  wire prefer_hot = (round != WEIGHT[15:0]);

  reg state;

  wire hot_avail  = |(row_req & hot_mask);
  wire cold_avail = |(row_req & cold_mask);
  wire use_hot  = (state == 1'b0) && ((prefer_hot && hot_avail) || (!prefer_hot && !cold_avail && hot_avail));
  wire use_cold = (state == 1'b0) && ((!prefer_hot && cold_avail) || (prefer_hot && !hot_avail && cold_avail));

  wire [7:0] hot_req_in  = use_hot  ? (row_req & hot_mask)  : 8'b0;
  wire [7:0] cold_req_in = use_cold ? (row_req & cold_mask) : 8'b0;
  wire [7:0] hot_gnt, cold_gnt;

  arbiter8 hot_arb (.clk(clk), .rst(rst), .req(hot_req_in),  .gnt(hot_gnt));
  arbiter8 cold_arb(.clk(clk), .rst(rst), .req(cold_req_in), .gnt(cold_gnt));

  wire [7:0] row_gnt = use_hot ? hot_gnt : (use_cold ? cold_gnt : 8'b0);
  reg [7:0] col_bitmap;

  function [2:0] idx8;
    input [7:0] bits;
    begin
      if (bits[0]) idx8 = 3'd0;
      else if (bits[1]) idx8 = 3'd1;
      else if (bits[2]) idx8 = 3'd2;
      else if (bits[3]) idx8 = 3'd3;
      else if (bits[4]) idx8 = 3'd4;
      else if (bits[5]) idx8 = 3'd5;
      else if (bits[6]) idx8 = 3'd6;
      else idx8 = 3'd7;
    end
  endfunction

  reg [7:0] sel_row_cols;
  always @(*) sel_row_cols = req[idx8(row_gnt)*8 +: 8];

  wire [7:0] col_bitmap_next = col_bitmap & (col_bitmap - 8'd1);
  integer k;

  always @(posedge clk) begin
    if (rst) begin
      state <= 1'b0; valid <= 1'b0; addr_type <= 1'b0; addr <= 3'd0; col_bitmap <= 8'd0; round <= 16'd0;
      decay_cnt <= {DECAY_SHIFT{1'b0}};
      tie_rotor <= 3'd0;
      for (k = 0; k < 8; k = k + 1) activity[k] <= 16'd0;
    end else begin
      tie_rotor <= tie_rotor + 3'd1;
      decay_cnt <= decay_cnt + 1'b1;
      for (k = 0; k < 8; k = k + 1) begin
        if (decay_tick)
          activity[k] <= (activity[k] >> 1) + {12'd0, row_new_cnt[k]};
        else
          activity[k] <= activity[k] + {12'd0, row_new_cnt[k]};
      end

      case (state)
        1'b0: begin
          if (|row_gnt) begin
            col_bitmap <= sel_row_cols;
            valid <= 1'b1;
            addr_type <= 1'b0;
            addr <= idx8(row_gnt);
            state <= 1'b1;
            round <= (round == WEIGHT[15:0]) ? 16'd0 : round + 16'd1;
          end else begin
            valid <= 1'b0;
          end
        end
        1'b1: begin
          if (col_bitmap != 8'd0) begin
            valid <= 1'b1;
            addr_type <= 1'b1;
            addr <= idx8(col_bitmap);
            col_bitmap <= col_bitmap_next;
            if (col_bitmap_next == 8'd0) state <= 1'b0;
          end else begin
            valid <= 1'b0;
            state <= 1'b0;
          end
        end
      endcase
    end
  end
endmodule
