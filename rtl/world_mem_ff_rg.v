// world_mem_ff와 같은 기능/포트(4096칸 x {valid,pol}, 단일 쓰기 + 호스트 읽기)를 행(y) 단위 클록 게이팅으로 명시 구현.
// 이유(§217): world_mem_ff는 Genus가 칸별 enable mux로 추론해 8192개 FF의 클록이 매 사이클 토글(레지스터 내부 전력이 전체의 77~90%). 여기서는 행마다 래치+AND 게이트를 두어
// 쓰는 행(64칸 x 2비트 = 128 FF)만 클록을 받는다. 행 안에서는 칸 enable로 값을 유지. 리셋 때는 모든 행 클록을 켜서 valid를 지움.
// ponytail: 행 64개 래치게이트, 행 안 칸 enable mux는 남음(칸별 ICG 4096개보다 작음). 읽기 4096:1 mux는 그대로.
module world_mem_ff_rg #(parameter integer ADDR_BITS = 12) (
  input                  clk,
  input                  rst,
  input                  we,
  input  [ADDR_BITS-1:0] addr,
  input                  pol,
  input  [ADDR_BITS-1:0] rd_addr,
  output                 rd_valid,
  output                 rd_pol
);
  localparam integer HB = ADDR_BITS / 2;           // 열(x) 비트 = 6, 행(y) 비트 = 6
  localparam integer ROWS = 1 << HB, COLS = 1 << HB;
  wire [HB-1:0] wy = addr[ADDR_BITS-1:HB];
  wire [HB-1:0] wx = addr[HB-1:0];
  reg  [ROWS*COLS-1:0] valid_r, pol_r;
  genvar r, c;
  generate
    for (r = 0; r < ROWS; r = r + 1) begin : ROW
      wire row_en = rst | (we & (wy == r));
      reg  en_l;
      always @(clk or row_en) if (!clk) en_l <= row_en;      // 낮은 구간에서 래치(글리치 없는 게이팅)
      wire gclk = clk & en_l;
      for (c = 0; c < COLS; c = c + 1) begin : COL
        always @(posedge gclk) begin
          if (rst) valid_r[r*COLS + c] <= 1'b0;
          else if (wx == c) begin valid_r[r*COLS + c] <= 1'b1; pol_r[r*COLS + c] <= pol; end
        end
      end
    end
  endgenerate
  assign rd_valid = valid_r[{rd_addr[ADDR_BITS-1:HB], rd_addr[HB-1:0]}];
  assign rd_pol   = pol_r[{rd_addr[ADDR_BITS-1:HB], rd_addr[HB-1:0]}];
endmodule
