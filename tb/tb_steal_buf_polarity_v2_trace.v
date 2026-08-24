// v2(full+grant 동시수락)의 실제 손실률을 공식 트레이스로 잼. arrival은 트레이스 비트를
// 그대로 펄스로 넣고(steal_buf류는 자체 pending_cnt를 들고 있어 TB admission 모델 불필요),
// overrun은 조합논리라 클럭 엣지 "전"에 샘플링(오늘 두 번 잡은 타이밍버그와 같은 종류를
// 처음부터 피함). polarity_in은 트레이스에 없으면 0으로 채움(손실률 측정 목적이라
// 극성값 자체는 무관 -- 극성 정확성은 tb_steal_buf_polarity_v2_correctness.v가 이미 검증).
`timescale 1ns/1ps
module tb_steal_buf_polarity_v2_trace;
  reg [1023:0] trace_file_r;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  wire [15:0] ov;
  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_v2 dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer i, cyc, drain_until;
  integer generated, dropped_overrun, delivered;
  reg [15:0] ov_sample;

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    generated = 0; dropped_overrun = 0; delivered = 0;
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin $display("CANNOT_OPEN_TRACE %0s", trace_file_r); $finish; end
    scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
    have_next = (scan_ret == 2);

    @(posedge clk); #1; rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0; polarity_in = 16'd0;
      if (have_next && next_cycle == cyc) begin
        arrival = next_mask[15:0];
        polarity_in = next_mask[15:0]; // 값은 무관(손실률 측정용), 아무 패턴이나 결정론적으로 사용
        for (i = 0; i < 16; i = i + 1) if (arrival[i]) generated = generated + 1;
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end
      #1;
      ov_sample = ov;
      for (i = 0; i < 16; i = i + 1) if (ov_sample[i]) dropped_overrun = dropped_overrun + 1;

      @(posedge clk); #1;
      if (v0) delivered = delivered + $countones(cm0);
      if (v1) delivered = delivered + $countones(cm1);

      cyc = cyc + 1;
    end

    arrival = 16'd0; polarity_in = 16'd0;
    drain_until = cyc + 15000;
    for (cyc = cyc; cyc < drain_until; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (v0) delivered = delivered + $countones(cm0);
      if (v1) delivered = delivered + $countones(cm1);
    end

    $display("TRACE=%0s generated=%0d delivered=%0d dropped_overrun=%0d", trace_file_r, generated, delivered, dropped_overrun);
    if (generated == delivered + dropped_overrun) $display("STEAL_BUF_POLARITY_V2_TRACE_PASS");
    else $display("STEAL_BUF_POLARITY_V2_TRACE_FAIL count_mismatch");
    $fclose(fd);
    $finish;
  end
endmodule
