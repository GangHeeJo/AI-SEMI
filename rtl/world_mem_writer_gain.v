// world_mem_writer + 생체 모방 이득 조절(gain control, §211/§212): 직전 W사이클 동안의 평균 도착률로 k = ceil(도착수/쓰기용량)를 정하고, 레인마다 확률 1/k로 받는다(의사난수 LFSR; 고정 간격 k번에 1번은 장면의 열 구조와 겹쳐 앨리어싱이 생겨 폐기, §212)
// (눈이 평균 밝기에 순응해 감도를 맞추는 것과 같은 방식). 1차 시도(FIFO 점유율로 k 결정)는 버스트 앞부분을 전부 받고 FIFO가 차면 그때부터 덜어내서 꼬리 버림과
// 같은 편향이 생겨 폐기 -- 버스트 안에서 고르게 덜어내려면 k가 버스트 시작 전에 정해져 있어야 한다.
// 쓰기 포트는 1건/사이클이므로 쓰기용량 = W. 걸러진 이벤트는 wr_shed로 센다. FIFO가 가득 차면 기존처럼 wr_overrun(꼬리 버림)이 안전망으로 남는다. stall은 쓰지 않음.
// ponytail: 창 W는 파라미터(기본 2048), k 상한 15. 레인별 4비트 위상 카운터 + 전역 도착 카운터 하나가 전부(칸별 기억 없음).
module world_mem_writer_gain #(
  parameter integer N_LANES    = 8,
  parameter integer ADDR_BITS  = 6,
  parameter integer FIFO_DEPTH = 32,
  parameter integer WIN_BITS   = 11                  // 추정 창 W = 2^WIN_BITS 사이클; 버스트 주기(프레임)보다 몇 배 길어야 k가 안 흔들림
)(
  input                             clk,
  input                             rst,
  input  [N_LANES-1:0]              wr_valid,
  input  [N_LANES*ADDR_BITS-1:0]    wr_x,
  input  [N_LANES*ADDR_BITS-1:0]    wr_y,
  input  [N_LANES-1:0]              wr_pol,
  output [N_LANES-1:0]              wr_overrun,
  output [N_LANES-1:0]              wr_shed,
  output                            stall,
  output                            world_we,
  output [2*ADDR_BITS-1:0]          world_addr,
  output                            world_pol
);
  localparam integer FIFO_W = 2 * ADDR_BITS + 1;
  wire [N_LANES-1:0] fifo_empty, fifo_full, fifo_near_full, gnt;
  wire [FIFO_W-1:0]  fifo_pop_data [0:N_LANES-1];
  reg  [3:0]         k_cur;                           // 현재 수용 간격(확률 1/k)
  reg  [15:0]        lfsr;                            // 공용 16비트 LFSR, 레인 g는 비트 [g+7:g]를 씀
  reg  [7:0]         thr;                             // 수용 문턱 = 256/k
  always @(*) case (k_cur)
    4'd2: thr = 8'd128; 4'd3: thr = 8'd85; 4'd4: thr = 8'd64; 4'd5: thr = 8'd51; 4'd6: thr = 8'd42; 4'd7: thr = 8'd36; 4'd8: thr = 8'd32;
    4'd9: thr = 8'd28; 4'd10: thr = 8'd25; 4'd11: thr = 8'd23; 4'd12: thr = 8'd21; 4'd13: thr = 8'd19; 4'd14: thr = 8'd18; 4'd15: thr = 8'd17;
    default: thr = 8'd255;
  endcase
  always @(posedge clk) begin
    if (rst) lfsr <= 16'hACE1;
    else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end
  reg  [WIN_BITS-1:0] win_cnt;
  reg  [WIN_BITS+3:0] arr_cnt;                         // 창 안 도착 이벤트 수(최대 8*W)
  integer pc;
  reg  [3:0]         pop_sum;
  wire [WIN_BITS+3:0] arr_next = arr_cnt + pop_sum;
  wire [WIN_BITS+3:0] k_calc = (arr_next + {WIN_BITS{1'b1}}) >> WIN_BITS;   // ceil(도착수 / W)
  always @(*) begin pop_sum = 4'd0; for (pc = 0; pc < N_LANES; pc = pc + 1) pop_sum = pop_sum + wr_valid[pc]; end
  always @(posedge clk) begin
    if (rst) begin win_cnt <= 0; arr_cnt <= 0; k_cur <= 4'd1; end
    else begin
      win_cnt <= win_cnt + 1'b1;
      if (&win_cnt) begin arr_cnt <= 0; k_cur <= (k_calc == 0) ? 4'd1 : (k_calc > 15) ? 4'd15 : k_calc[3:0]; end
      else arr_cnt <= arr_next;
    end
  end
  wire [N_LANES-1:0] accept;

  genvar g;
  generate
    for (g = 0; g < N_LANES; g = g + 1) begin : LANE
      assign accept[g] = (k_cur == 4'd1) || (lfsr[g +: 8] < thr);
      small_fifo #(.WIDTH(FIFO_W), .DEPTH(FIFO_DEPTH), .MARGIN(2)) u_fifo (
        .clk(clk), .rst(rst),
        .push(wr_valid[g] & accept[g]),
        .push_data({wr_y[g*ADDR_BITS +: ADDR_BITS], wr_x[g*ADDR_BITS +: ADDR_BITS], wr_pol[g]}),
        .pop(gnt[g]), .pop_data(fifo_pop_data[g]),
        .empty(fifo_empty[g]), .full(fifo_full[g]), .near_full(fifo_near_full[g])
      );
    end
  endgenerate

  assign wr_overrun = wr_valid & accept & fifo_full;
  assign wr_shed    = wr_valid & ~accept;
  assign stall      = 1'b0;

  arbiter8 u_arb (.clk(clk), .rst(rst), .req(~fifo_empty), .gnt(gnt));
  wire any_gnt = |gnt;
  reg [FIFO_W-1:0] sel_data;
  integer k;
  always @(*) begin
    sel_data = {FIFO_W{1'b0}};
    for (k = 0; k < N_LANES; k = k + 1) if (gnt[k]) sel_data = fifo_pop_data[k];
  end
  assign world_we   = any_gnt;
  assign world_addr = {sel_data[FIFO_W-1 -: ADDR_BITS], sel_data[ADDR_BITS -: ADDR_BITS]};
  assign world_pol  = sel_data[0];
endmodule
