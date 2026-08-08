// naive(전통 flat AER) vs base(행-열+burst) 상시포화(saturation) 처리량 비교.
// 목적: "base가 naive보다 항상 좋다"가 아니라 "공간적 상관관계(같은 행 동시발화)가
// 있을 때만 base가 유리하고, 완전히 고립된 트래픽에서는 naive가 오히려 유리할 수
// 있다"는 걸 실측으로 보여줌. 클럭 자체는 안 바꾸고(같은 clk), 사이클당 처리량만
// 재고, 각자의 실측 진짜 Fmax(naive 556MHz, base 833MHz, progress.md 5-22)를
// 곱해서 실시간(초당 이벤트) 환산치까지 같이 출력한다.
`timescale 1ns/1ps
module tb_naive_vs_base_saturation;
  parameter CYCLES = 2000;
  parameter real NAIVE_FMAX_MHZ = 556.0;
  parameter real BASE_FMAX_MHZ  = 833.3;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  always #5 clk = ~clk;

  wire naive_valid;
  wire [3:0] naive_addr;
  aer_tx16_naive n_tx(.clk(clk), .rst(rst), .req(req), .valid(naive_valid), .addr(naive_addr));

  wire b_valid, b_addr_type;
  wire [1:0] b_addr;
  wire [15:0] b_captured;
  wire b_event_valid;
  wire [1:0] b_erow, b_ecol;
  aer_tx16 b_tx(.clk(clk), .rst(rst), .req(req), .valid(b_valid), .addr_type(b_addr_type), .addr(b_addr), .captured(b_captured));
  aer_rx16 b_rx(.clk(clk), .rst(rst), .valid(b_valid), .addr_type(b_addr_type), .addr(b_addr),
                .event_valid(b_event_valid), .event_row(b_erow), .event_col(b_ecol));

  integer naive_count, base_count, cyc;
  real naive_ev_per_cyc, base_ev_per_cyc;

  initial begin
    // ---- 시나리오 1: 공간적 상관관계 최대(16개 전부 상시 요청, 매 행마다 4열 동시발화) ----
    rst = 1; req = 16'b0; naive_count = 0; base_count = 0;
    @(posedge clk); #1; rst = 0;
    req = 16'hFFFF;
    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (naive_valid) naive_count = naive_count + 1;
      if (b_event_valid) base_count = base_count + 1;
    end
    naive_ev_per_cyc = naive_count * 1.0 / CYCLES;
    base_ev_per_cyc  = base_count * 1.0 / CYCLES;
    $display("=== 시나리오1: correlated(16개 전부 상시 요청 = 매 행 4열 동시발화) ===");
    $display("  naive: %0d events / %0d cyc = %f ev/cyc  ->  %f Mevents/s (@%fMHz)",
              naive_count, CYCLES, naive_ev_per_cyc, naive_ev_per_cyc * NAIVE_FMAX_MHZ, NAIVE_FMAX_MHZ);
    $display("  base : %0d events / %0d cyc = %f ev/cyc  ->  %f Mevents/s (@%fMHz)",
              base_count, CYCLES, base_ev_per_cyc, base_ev_per_cyc * BASE_FMAX_MHZ, BASE_FMAX_MHZ);

    // ---- 시나리오 2: 공간적 상관관계 0(고립된 셀 1개만 영원히 상시 요청) ----
    rst = 1; req = 16'b0; naive_count = 0; base_count = 0;
    @(posedge clk); #1; rst = 0;
    req = 16'b0000000000000001; // idx0 (row0,col0) 하나만 계속 요청 -> 절대 batching 불가
    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (naive_valid) naive_count = naive_count + 1;
      if (b_event_valid) base_count = base_count + 1;
    end
    naive_ev_per_cyc = naive_count * 1.0 / CYCLES;
    base_ev_per_cyc  = base_count * 1.0 / CYCLES;
    $display("=== 시나리오2: decorrelated(고립된 셀 1개만 상시 요청 = 공간적 상관관계 0) ===");
    $display("  naive: %0d events / %0d cyc = %f ev/cyc  ->  %f Mevents/s (@%fMHz)",
              naive_count, CYCLES, naive_ev_per_cyc, naive_ev_per_cyc * NAIVE_FMAX_MHZ, NAIVE_FMAX_MHZ);
    $display("  base : %0d events / %0d cyc = %f ev/cyc  ->  %f Mevents/s (@%fMHz)",
              base_count, CYCLES, base_ev_per_cyc, base_ev_per_cyc * BASE_FMAX_MHZ, BASE_FMAX_MHZ);

    $finish;
  end
endmodule
