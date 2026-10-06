// 월드 메모리(4096칸 x {valid, pol} 2비트)를 플립플롭 배열로 직접 구현 -- GPDK045에 SRAM 매크로가 없어서(현수 실측: FF+클록게이팅이
// Layout/PEX/Post-Sim이 전부 닫히는 방식). 쓰기는 world_mem_writer의 단일 포트(we/addr/pol), 읽기는 호스트용 조합 읽기 포트(없으면 합성이 배열을 지움).
// valid만 리셋(극성 비트는 valid가 서기 전엔 의미 없음). ponytail: 4096:1 읽기 mux가 면적을 먹음, 줄이려면 읽기를 직렬 스캔으로.
module world_mem_ff #(parameter integer ADDR_BITS = 12) (
  input                  clk,
  input                  rst,
  input                  we,
  input  [ADDR_BITS-1:0] addr,
  input                  pol,
  input  [ADDR_BITS-1:0] rd_addr,
  output                 rd_valid,
  output                 rd_pol
);
  localparam integer DEPTH = 1 << ADDR_BITS;
  reg [DEPTH-1:0] valid_r;
  reg [DEPTH-1:0] pol_r;
  integer i;
  always @(posedge clk) begin
    if (rst) valid_r <= {DEPTH{1'b0}};
    else if (we) valid_r[addr] <= 1'b1;
  end
  always @(posedge clk) if (we) pol_r[addr] <= pol;
  assign rd_valid = valid_r[rd_addr];
  assign rd_pol   = pol_r[rd_addr];
endmodule
