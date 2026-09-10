// Digital 2차 1단계 통합 -- coord_transform_rmcm 8레인 결과(X,Y,pol)를 world memory에 쓴다.
//
// v3(2026-09-10): v2(FIFO+arbiter8, 진짜 단일 포트로 줄임)는 방향은 맞았지만 여전히 4096칸을
// RTL 레지스터 배열로 "합성"하고 있었음 -- 포트를 1개로 줄여도 저장소 자체(플립플롭 4096개)가
// 원래 비싼 거라 근본 해결이 아니었음. 실제 ASIC/FPGA라면 이 정도 규모 저장소는 SRAM
// 매크로/BRAM으로 만드는 게 표준이라, 이 모듈은 이제 **저장소를 합성하지 않고** "8레인 경합을
// 진짜 단일 SRAM 쓰기 포트(we/addr/data) 하나로 직렬화하는 것"까지만 담당한다 -- 그 뒤에
// 붙는 실제 저장소는 시뮬레이션에선 테스트벤치 메모리 모델, FPGA에선 BRAM, ASIC에선 SRAM
// 매크로로 각자 붙이면 됨(이 파일이 합성 PPA로 잡히지 않음).
//
// FIFO+arbiter8 부분은 v2와 동일: 레인마다 작은 FIFO(깊이 파라미터화, `small_fifo.v`)로
// 버퍼링하고 arbiter8로 매 사이클 1개만 골라 커밋한다.
module world_mem_writer #(
  parameter integer N_LANES    = 8,
  parameter integer ADDR_BITS  = 6,
  parameter integer FIFO_DEPTH = 32 // 실측(§114): 실트래픽에서 깊이4=13.3% overrun, 16=0.01%, 32=0%
)(
  input                             clk,
  input                             rst,
  input  [N_LANES-1:0]              wr_valid,
  input  [N_LANES*ADDR_BITS-1:0]    wr_x,
  input  [N_LANES*ADDR_BITS-1:0]    wr_y,
  input  [N_LANES-1:0]              wr_pol,
  output [N_LANES-1:0]              wr_overrun,

  // SRAM 스타일 단일 쓰기 포트 -- 실제 저장소는 이 인터페이스 바깥(테스트벤치 모델/BRAM/
  // SRAM 매크로)에 붙는다.
  output                            world_we,
  output [2*ADDR_BITS-1:0]          world_addr,
  output                            world_pol
);
  localparam integer FIFO_W = 2 * ADDR_BITS + 1;  // {y, x, pol}

  wire [N_LANES-1:0]   fifo_empty;
  wire [N_LANES-1:0]   fifo_full;
  wire [N_LANES-1:0]   gnt;
  wire [FIFO_W-1:0]    fifo_pop_data [0:N_LANES-1];

  assign wr_overrun = wr_valid & fifo_full;

  genvar g;
  generate
    for (g = 0; g < N_LANES; g = g + 1) begin : FIFO
      small_fifo #(.WIDTH(FIFO_W), .DEPTH(FIFO_DEPTH)) u_fifo (
        .clk(clk), .rst(rst),
        .push(wr_valid[g]),
        .push_data({wr_y[g*ADDR_BITS +: ADDR_BITS], wr_x[g*ADDR_BITS +: ADDR_BITS], wr_pol[g]}),
        .pop(gnt[g]),
        .pop_data(fifo_pop_data[g]),
        .empty(fifo_empty[g]),
        .full(fifo_full[g])
      );
    end
  endgenerate

  arbiter8 u_arb (.clk(clk), .rst(rst), .req(~fifo_empty), .gnt(gnt));

  wire any_gnt = |gnt;
  reg [FIFO_W-1:0] sel_data;
  integer k;
  always @(*) begin
    sel_data = {FIFO_W{1'b0}};
    for (k = 0; k < N_LANES; k = k + 1)
      if (gnt[k]) sel_data = fifo_pop_data[k];
  end

  assign world_we   = any_gnt;
  assign world_addr = {sel_data[FIFO_W-1 -: ADDR_BITS], sel_data[ADDR_BITS -: ADDR_BITS]}; // {y, x}
  assign world_pol  = sel_data[0];
endmodule
