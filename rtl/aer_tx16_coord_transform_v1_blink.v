// "눈 깜빡임"(§217): 이벤트가 없는 구간에 코어(aer_tx16_coord_transform_v1) 클록을 통째로 끈다. 월드 메모리(world_mem_ff_rg)는 자체 행 게이팅이라 자유 클록에 둔다.
// 켜짐 조건: 어떤 소스든 arrival이 오는 사이클, 또는 마지막 arrival 후 TIMEOUT 사이클 이내(FIFO/버퍼가 다 비워질 시간), 또는 리셋 중.
// TIMEOUT은 쓰기 FIFO 최대 적재(8레인 x 32 = 256) + 파이프라인 여유로 정함. 이 시간 안에 못 비워지면 데이터가 멈추므로 검증은 메모리 이미지를 v1과 비교.
// 래치 기반 게이트(글리치 없음): 클록 낮은 구간에서 enable을 잡는다. arrival은 같은 사이클에 들어와도 그 사이클 끝 엣지부터 코어가 받는다.
module aer_tx16_coord_transform_v1_blink #(parameter integer TIMEOUT = 511) (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  input  [7:0]  theta_idx,
  output [15:0] overrun,
  output [7:0]  wmem_overrun,
  input  [11:0] rd_addr,
  output        rd_valid,
  output        rd_pol,
  output        core_clk_on        // 관측용(전력 통계/테스트)
);
  reg [9:0] hold;                                        // 마지막 arrival 이후 남은 유지 시간
  wire any_arr = |arrival;
  always @(posedge clk) begin
    if (rst) hold <= TIMEOUT[9:0];
    else if (any_arr) hold <= TIMEOUT[9:0];
    else if (hold != 0) hold <= hold - 1'b1;
  end
  wire enable = rst | any_arr | (hold != 0);
  reg en_l;
  always @(clk or enable) if (!clk) en_l <= enable;
  wire gclk = clk & en_l;
  assign core_clk_on = en_l;

  wire        world_we, world_pol;
  wire [11:0] world_addr;
  aer_tx16_coord_transform_v1 u_core (
    .clk(gclk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
    .overrun(overrun), .wmem_overrun(wmem_overrun),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );
  world_mem_ff_rg #(.ADDR_BITS(12)) u_mem (
    .clk(clk), .rst(rst), .we(world_we), .addr(world_addr), .pol(world_pol),
    .rd_addr(rd_addr), .rd_valid(rd_valid), .rd_pol(rd_pol)
  );
endmodule
