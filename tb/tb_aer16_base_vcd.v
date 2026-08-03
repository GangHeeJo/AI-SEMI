// base(aer_tx16)의 활동도 기반(activity-based) 전력 측정용 VCD 생성.
// 기존 PPA 비교에 쓴 것과 똑같은 시나리오(ARRIVAL_PCT=15%, CYCLES=3000, seed=1)를 재현해서,
// Genus의 vectorless(추정치) 전력 대신 "진짜 스위칭 활동" 기반 전력을 나중에 서버에서 잴 수 있게 함.
// `timescale을 명시 안 하면 Icarus 기본값(1s)이 찍혀서 Genus의 VCD 파서가 거부함(STIM-1010) —
// 5ns 클럭 SDC와 맞춰 1ns/1ps로 명시. #5 딜레이가 이제 진짜 5ns를 의미하게 됨(원래도 논리적
// 타이밍 관계는 동일했고, 물리적 단위 해석만 5s에서 5ns로 바뀜 — 결과 자체는 안 바뀜).
`timescale 1ns/1ps
module tb_aer16_base_vcd;
  parameter CYCLES = 3000;
  parameter ARRIVAL_PCT = 15;
  parameter QDEPTH = 32;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  aer_tx16 tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, idx;
  integer phantom_errors;

  initial begin
    $dumpfile("aer_tx16_base.vcd");
    $dumpvars(0, tb_aer16_base_vcd);

    rst = 1; req = 16'd0; phantom_errors = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < ARRIVAL_PCT) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (event_valid) begin
        idx = event_row*4 + event_col;
        if (score.record_departure(idx, cyc) < 0) phantom_errors = phantom_errors + 1;
      end
    end

    if (phantom_errors > 0)
      $display("WARNING: phantom 이벤트 %0d건 — VCD가 비정상 시나리오를 담았을 수 있음", phantom_errors);
    $display("VCD 생성 완료: aer_tx16_base.vcd (%0d cycles, ARRIVAL_PCT=%0d%%, phantom=%0d)", CYCLES, ARRIVAL_PCT, phantom_errors);
    $finish;
  end
endmodule
