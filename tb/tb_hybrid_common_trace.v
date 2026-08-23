// 하이브리드(cluster2+dense bitmap)를 준영 공용 trace(cyclemask 포맷)로 검증.
// tb_cluster2_steal_common_trace.v와 완전히 동일한 배선 재현(native_ack_mask=
// result_mask&pending 조합논리, native_req=pending&~ack_mask 같은 사이클 재구동 방지,
// pending 클리어는 논블로킹이라 1사이클 늦게 반영) -- 이번엔 mode/bitmap 출력까지 포함.
`timescale 1ns/1ps
module tb_hybrid_common_trace;
  parameter DRAIN_CYCLES = 3000;
  parameter THRESH = 2;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire mode_w;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;
  wire [15:0] bitmap_w;

  aer_tx16_hybrid_cluster2_bitmap #(.ROW_THRESHOLD(THRESH)) dut(
    .clk(clk), .rst(rst), .req(req),
    .mode(mode_w),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .bitmap(bitmap_w));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked, phantom_count;
  integer addressed_cycles, bitmap_cycles;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic decode_result;
    output reg [15:0] rmask;
    integer k;
    begin
      rmask = 16'd0;
      if (mode_w) begin
        rmask = bitmap_w;
      end else begin
        if (valid0_w) for (k = 0; k < 4; k = k + 1) if (colmask0_w[k]) rmask[row0_w*4+k] = 1'b1;
        if (valid1_w) for (k = 0; k < 4; k = k + 1) if (colmask1_w[k]) rmask[row1_w*4+k] = 1'b1;
      end
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0; phantom_count = 0;
    addressed_cycles = 0; bitmap_cycles = 0;
    pending = 16'd0; pending_clear_q = 16'd0;
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
      pending = pending & ~pending_clear_q;

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

      decode_result(result_mask);
      if ((result_mask & ~pending) != 16'd0) begin
        phantom_count = phantom_count + popcount16(result_mask & ~pending);
      end
      if (mode_w) bitmap_cycles = bitmap_cycles + 1; else addressed_cycles = addressed_cycles + 1;

      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);

      req = pending & ~ack_mask;

      pending_clear_q = ack_mask;

      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~pending_clear_q;

      decode_result(result_mask);
      if ((result_mask & ~pending) != 16'd0)
        phantom_count = phantom_count + popcount16(result_mask & ~pending);
      if (mode_w) bitmap_cycles = bitmap_cycles + 1; else addressed_cycles = addressed_cycles + 1;

      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);
      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;

      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d(%0d.%0d%%) acked=%0d accepted_check=%0d phantom=%0d addr_cyc=%0d bm_cyc=%0d",
      trace_file_r, generated, overrun, (overrun*100)/generated, ((overrun*1000)/generated)%10,
      acked, generated-overrun, phantom_count, addressed_cycles, bitmap_cycles);
    if (phantom_count == 0 && (acked == generated - overrun))
      $display("HYBRID_TRACE_PASS %0s", trace_file_r);
    else
      $display("HYBRID_TRACE_FAIL %0s phantom=%0d acked=%0d expected=%0d", trace_file_r, phantom_count, acked, generated-overrun);
    $fclose(fd);
    $finish;
  end
endmodule
