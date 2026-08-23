// aer_tx16_adaptive2_serial(+RX)를 공식 50-workload trace로 검증. §82의 조합논리
// "무제한용량, 즉시배달" 가정이 실제 순차(멀티사이클) RTL에서도 정확성(무손실, 팬텀 0)과
// 비용(핀-사이클) 양쪽에서 성립하는지 확인. cluster2 native(C2_bits, §82에서 이미 확정된
// 정확한 admission 모델 재사용)와 이번엔 "핀-사이클"(=link폭4 * 사용사이클)로 공정 비교.
`timescale 1ns/1ps
module tb_adaptive2_serial_common_trace;
  parameter DRAIN_CYCLES = 4000;
  parameter LINK_WIDTH = 4;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire link_valid;
  wire [3:0] link_data;
  wire [15:0] ack_mask;
  wire [15:0] decoded_mask;
  wire decoded_valid;

  aer_tx16_adaptive2_serial tx(
    .clk(clk), .rst(rst), .req(req),
    .link_valid(link_valid), .link_data(link_data), .ack_mask(ack_mask));
  aer_rx16_adaptive2_serial rx(
    .clk(clk), .rst(rst),
    .link_valid(link_valid), .link_data(link_data),
    .decoded_mask(decoded_mask), .decoded_valid(decoded_valid));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i;
  reg [15:0] pending;
  integer generated, overrun, delivered_events;
  integer link_busy_cycles;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  initial begin
    generated = 0; overrun = 0; delivered_events = 0; link_busy_cycles = 0;
    pending = 16'd0;
    rst = 1; req = 16'd0;
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin $display("CANNOT_OPEN_TRACE %0s", trace_file_r); $finish; end
    scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
    have_next = (scan_ret == 2);

    @(posedge clk); #1;
    rst = 0;

    cyc = 0;
    while (have_next) begin
      // ack된 소스는 TX가 nonblocking으로 낸 ack_mask를 이번 관찰 시점에 즉시 반영
      pending = pending & ~ack_mask;

      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) begin
          if (next_mask[i]) begin
            generated = generated + 1;
            if (pending[i]) overrun = overrun + 1; else pending[i] = 1'b1;
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end

      req = pending;
      if (link_valid) link_busy_cycles = link_busy_cycles + 1;
      // ack_mask(현재 사이클)와 decoded_mask/decoded_valid(1사이클 뒤 -- RX가 그
      // 마지막 청크를 "받아서" 완성하는 시점)는 정의상 1사이클 어긋나므로 여기서
      // 직접 비교하지 않음(둘 다 같은 cap_mask를 가리킨다는 건 §exhaustive에서
      // 65535개 패턴 전수로 이미 증명됨). 여기선 "보낸 만큼 정확히 받았는가"만 집계.
      if (decoded_valid) delivered_events = delivered_events + popcount16(decoded_mask);

      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~ack_mask;
      req = pending;
      if (link_valid) link_busy_cycles = link_busy_cycles + 1;
      if (decoded_valid) delivered_events = delivered_events + popcount16(decoded_mask);
      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d delivered=%0d link_busy_cycles=%0d pin_cycles=%0d",
      trace_file_r, generated, overrun, delivered_events,
      link_busy_cycles, link_busy_cycles * LINK_WIDTH);
    if (delivered_events == generated - overrun)
      $display("ADAPTIVE2_SERIAL_TRACE_PASS %0s", trace_file_r);
    else
      $display("ADAPTIVE2_SERIAL_TRACE_FAIL %0s delivered=%0d expected=%0d", trace_file_r, delivered_events, generated-overrun);
    $fclose(fd);
    $finish;
  end
endmodule
