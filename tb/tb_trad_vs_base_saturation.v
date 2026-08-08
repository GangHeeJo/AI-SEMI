// true_traditional(행-열 계층, burst 없음) vs base(행-열+burst) 상시포화 처리량 비교.
// naive_vs_base_saturation.v와 동일한 방법론이지만 진짜 문헌상의 전통 AER인
// true_traditional을 기준점으로 재비교(progress.md #17 — naive는 비교대상 아님).
`timescale 1ns/1ps
module tb_trad_vs_base_saturation;
  parameter CYCLES = 2000;
  parameter real TRAD_FMAX_MHZ = 645.0;
  parameter real BASE_FMAX_MHZ = 800.0;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  always #5 clk = ~clk;

  wire trad_valid;
  wire [3:0] trad_addr;
  aer_tx16_trad_rowcol t_tx(.clk(clk), .rst(rst), .req(req), .valid(trad_valid), .addr(trad_addr));

  wire b_valid, b_addr_type;
  wire [1:0] b_addr;
  wire [1:0] b_captured_row;
  wire [3:0] b_captured_cols;
  wire b_event_valid;
  wire [1:0] b_erow, b_ecol;
  aer_tx16 b_tx(.clk(clk), .rst(rst), .req(req), .valid(b_valid), .addr_type(b_addr_type), .addr(b_addr),
                .captured_row(b_captured_row), .captured_cols(b_captured_cols));
  aer_rx16 b_rx(.clk(clk), .rst(rst), .valid(b_valid), .addr_type(b_addr_type), .addr(b_addr),
                .event_valid(b_event_valid), .event_row(b_erow), .event_col(b_ecol));

  integer trad_count, base_count, cyc;
  real trad_ev_per_cyc, base_ev_per_cyc;

  initial begin
    // ---- 시나리오1: correlated(16개 전부 상시 요청 = 매 행 4열 동시발화) ----
    rst = 1; req = 16'b0; trad_count = 0; base_count = 0;
    @(posedge clk); #1; rst = 0;
    req = 16'hFFFF;
    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (trad_valid) trad_count = trad_count + 1;
      if (b_event_valid) base_count = base_count + 1;
    end
    trad_ev_per_cyc = trad_count * 1.0 / CYCLES;
    base_ev_per_cyc = base_count * 1.0 / CYCLES;
    $display("=== 시나리오1: correlated(16개 전부 상시 요청) ===");
    $display("  true_traditional: %0d/%0d = %f ev/cyc -> %f Mevents/s (@%fMHz)",
              trad_count, CYCLES, trad_ev_per_cyc, trad_ev_per_cyc * TRAD_FMAX_MHZ, TRAD_FMAX_MHZ);
    $display("  base            : %0d/%0d = %f ev/cyc -> %f Mevents/s (@%fMHz)",
              base_count, CYCLES, base_ev_per_cyc, base_ev_per_cyc * BASE_FMAX_MHZ, BASE_FMAX_MHZ);

    // ---- 시나리오2: decorrelated(고립된 셀 1개만 상시 요청) ----
    rst = 1; req = 16'b0; trad_count = 0; base_count = 0;
    @(posedge clk); #1; rst = 0;
    req = 16'b0000000000000001;
    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (trad_valid) trad_count = trad_count + 1;
      if (b_event_valid) base_count = base_count + 1;
    end
    trad_ev_per_cyc = trad_count * 1.0 / CYCLES;
    base_ev_per_cyc = base_count * 1.0 / CYCLES;
    $display("=== 시나리오2: decorrelated(고립된 셀 1개만 상시 요청) ===");
    $display("  true_traditional: %0d/%0d = %f ev/cyc -> %f Mevents/s (@%fMHz)",
              trad_count, CYCLES, trad_ev_per_cyc, trad_ev_per_cyc * TRAD_FMAX_MHZ, TRAD_FMAX_MHZ);
    $display("  base            : %0d/%0d = %f ev/cyc -> %f Mevents/s (@%fMHz)",
              base_count, CYCLES, base_ev_per_cyc, base_ev_per_cyc * BASE_FMAX_MHZ, BASE_FMAX_MHZ);

    $finish;
  end
endmodule
