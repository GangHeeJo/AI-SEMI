// v2: "full+grant 동시 수락" 최적화 -- 소스의 2-deep FIFO가 꽉 찬 상태라도, 이번 사이클에
// 그 소스가 마침 grant돼서 자리 하나가 비면(같은 clock edge 안에서 pop과 push가 동시에
// 일어남) 새 도착을 받아줌. 원본(v1, aer_tx16_..._steal_buf_polarity.v)은 old depth==2일
// 때 grant가 나도 "arrival && !pending_full"이 0이라 case 2'b01(pop만)로 떨어져서 새
// 도착을 무조건 버렸음(overrun) -- 이 사이클에 자리가 비는 걸 알면서도 못 쓰는 손실이었음.
//
// admission 조건 변경: overrun은 "꽉 찼는데 이번 사이클에 안 비워질 때"만.
//   accept_arrival[i] = arrival[i] && (!pending_full[i] || granted_bitmap[i])
//   overrun[i]        = arrival[i] &&  pending_full[i]  && ~granted_bitmap[i]
//
// FIFO 갱신은 old depth로 분기해야 함(2'b11 케이스가 이제 old depth 1 또는 2 둘 다 가능해져서
// 단순 2비트 case만으로는 구분이 안 됨 -- pending_cnt[pc_k]로 직접 분기):
//   old depth==2, grant, accept_arrival: pol_fifo0<=pol_fifo1(시프트), pol_fifo1<=new(뒤에 push), depth 그대로 2(하나 나가고 하나 들어옴)
//   old depth==1, grant, accept_arrival: pol_fifo0<=new(비운 자리에 바로 채움), depth 그대로 1(§v1과 동일)
//   grant, 도착 없음: depth==2면 시프트(pop), depth==1이면 그냥 감소
//   grant 없음, accept_arrival: depth 0->1(front에 push) 또는 1->2(back에 push)
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_v2 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  output [15:0] overrun,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg [3:0]  pol_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg [3:0]  pol_mask1
);
  reg [1:0] pending_cnt [0:15];
  reg pol_fifo0 [0:15];
  reg pol_fifo1 [0:15];
  integer pc_k;

  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  wire [15:0] pol_front_bus;
  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = (pending_cnt[gk] != 2'd0);
      assign pending_full[gk] = (pending_cnt[gk] == 2'd2);
      assign pol_front_bus[gk] = pol_fifo0[gk];
    end
  endgenerate

  wire [3:0] row_req;
  assign row_req[0] = |pending_gt0[3:0];
  assign row_req[1] = |pending_gt0[7:4];
  assign row_req[2] = |pending_gt0[11:8];
  assign row_req[3] = |pending_gt0[15:12];

  wire center_r1 = row_req[1];
  wire center_r2 = row_req[2];
  wire periph_r0 = row_req[0];
  wire periph_r3 = row_req[3];
  wire center_idle = ~(center_r1 | center_r2);
  wire periph_idle = ~(periph_r0 | periph_r3);
  wire steal_to_periph = center_idle & periph_r0 & periph_r3;
  wire steal_to_center = periph_idle & center_r1 & center_r2;

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  reg lane0_valid_c;
  reg [1:0] lane0_row_c;
  reg [3:0] lane0_cols_c;
  reg [3:0] lane0_pol_c;
  always @(*) begin
    if (steal_to_center) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd1;
      lane0_cols_c = pending_gt0[7:4];   lane0_pol_c = pol_front_bus[7:4];
    end else if (~center_idle) begin
      lane0_valid_c = 1'b1;
      lane0_row_c  = center_gnt[1] ? 2'd1 : 2'd2;
      lane0_cols_c = center_gnt[1] ? pending_gt0[7:4]   : pending_gt0[11:8];
      lane0_pol_c  = center_gnt[1] ? pol_front_bus[7:4] : pol_front_bus[11:8];
    end else if (steal_to_periph) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd0;
      lane0_cols_c = pending_gt0[3:0];   lane0_pol_c = pol_front_bus[3:0];
    end else begin
      lane0_valid_c = 1'b0; lane0_row_c = 2'd0; lane0_cols_c = 4'd0; lane0_pol_c = 4'd0;
    end
  end

  reg lane1_valid_c;
  reg [1:0] lane1_row_c;
  reg [3:0] lane1_cols_c;
  reg [3:0] lane1_pol_c;
  always @(*) begin
    if (steal_to_periph) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd3;
      lane1_cols_c = pending_gt0[15:12]; lane1_pol_c = pol_front_bus[15:12];
    end else if (~periph_idle) begin
      lane1_valid_c = 1'b1;
      lane1_row_c  = periph_gnt[0] ? 2'd0 : 2'd3;
      lane1_cols_c = periph_gnt[0] ? pending_gt0[3:0]    : pending_gt0[15:12];
      lane1_pol_c  = periph_gnt[0] ? pol_front_bus[3:0]  : pol_front_bus[15:12];
    end else if (steal_to_center) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd2;
      lane1_cols_c = pending_gt0[11:8];  lane1_pol_c = pol_front_bus[11:8];
    end else begin
      lane1_valid_c = 1'b0; lane1_row_c = 2'd0; lane1_cols_c = 4'd0; lane1_pol_c = 4'd0;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; pol_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; pol_mask1 <= 4'd0;
    end else begin
      valid0 <= lane0_valid_c; row0 <= lane0_row_c; col_mask0 <= lane0_cols_c; pol_mask0 <= lane0_pol_c;
      valid1 <= lane1_valid_c; row1 <= lane1_row_c; col_mask1 <= lane1_cols_c; pol_mask1 <= lane1_pol_c;
    end
  end

  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

  wire [15:0] accept_arrival = arrival & (~pending_full | granted_bitmap);
  assign overrun = arrival & pending_full & ~granted_bitmap;

  always @(posedge clk) begin
    if (rst) begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        pending_cnt[pc_k] <= 2'd0; pol_fifo0[pc_k] <= 1'b0; pol_fifo1[pc_k] <= 1'b0;
      end
    end else begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        if (granted_bitmap[pc_k]) begin
          if (pending_cnt[pc_k] == 2'd2) begin
            pol_fifo0[pc_k] <= pol_fifo1[pc_k];
            if (accept_arrival[pc_k]) begin
              pol_fifo1[pc_k] <= polarity_in[pc_k];
              pending_cnt[pc_k] <= 2'd2; // 하나 나가고 하나 들어옴, 순증감 0
            end else begin
              pending_cnt[pc_k] <= 2'd1;
            end
          end else begin // old depth == 1 (grant는 depth>0일 때만 나므로 나머지는 1)
            if (accept_arrival[pc_k]) begin
              pol_fifo0[pc_k] <= polarity_in[pc_k];
              pending_cnt[pc_k] <= 2'd1; // 순증감 0
            end else begin
              pending_cnt[pc_k] <= 2'd0;
            end
          end
        end else begin
          if (accept_arrival[pc_k]) begin // grant 없을 때 accept면 full이 아니었다는 뜻(depth 0 or 1)
            if (pending_cnt[pc_k] == 2'd0) pol_fifo0[pc_k] <= polarity_in[pc_k];
            else pol_fifo1[pc_k] <= polarity_in[pc_k];
            pending_cnt[pc_k] <= pending_cnt[pc_k] + 2'd1;
          end
        end
      end
    end
  end
endmodule
