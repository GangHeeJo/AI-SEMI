// 시뮬레이션 전용 동작 모델 -- 1-cycle latency 단일포트 동기 SRAM. rtl/bayes_filter.v(§134)가
// 기대하는 world memory 인터페이스(addr/we/wdata/rdata)를 테스트벤치에서 흉내낸다. 실제
// ASIC/FPGA에서는 이 자리에 SRAM 매크로/BRAM이 들어간다(world_mem_writer.v와 같은 관례로
// 저장소 자체는 RTL 합성 대상 밖에 둠).
module sync_sram_1rw #(
  parameter integer ADDR_BITS = 20,
  parameter integer DATA_BITS = 8
)(
  input                       clk,
  input      [ADDR_BITS-1:0]  addr,
  input                       we,
  input      [DATA_BITS-1:0]  wdata,
  output reg [DATA_BITS-1:0]  rdata
);
  reg [DATA_BITS-1:0] mem [0:(1<<ADDR_BITS)-1];
  integer i;
  initial for (i = 0; i < (1<<ADDR_BITS); i = i + 1) mem[i] = {DATA_BITS{1'b0}};

  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    else    rdata <= mem[addr];
  end
endmodule
