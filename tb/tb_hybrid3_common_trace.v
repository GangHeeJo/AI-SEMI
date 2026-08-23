// 3-way(cluster2+bitmap+repeat) 결합을 공용 trace로 검증 + 비트비용 실측.
// 배선은 tb_hybrid_common_trace.v와 동일(native_ack_mask/native_req/논블로킹 지연).
// 비트비용: addressed 그랜트는 repeat면 1b, 아니면 7b(flag1+row2+colmask4).
// bitmap 사이클은 고정 16b(§69/§70과 동일 회계).
`timescale 1ns/1ps
module tb_hybrid3_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire mode_w;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w; wire rep0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w; wire rep1_w;
  wire [15:0] bitmap_w;

  aer_tx16_hybrid3_bitmap_repeat dut(
    .clk(clk), .rst(rst), .req(req),
    .mode(mode_w),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w), .repeat0(rep0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w), .repeat1(rep1_w),
    .bitmap(bitmap_w));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked, phantom_count;
  integer bits_total, addr_cyc, bm_cyc, repeat_hits, new_hits;

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

  task automatic account_bits;
    begin
      if (mode_w) begin
        bm_cyc = bm_cyc + 1;
        bits_total = bits_total + 16;
      end else begin
        addr_cyc = addr_cyc + 1;
        if (valid0_w) begin
          bits_total = bits_total + (rep0_w ? 1 : 7);
          if (rep0_w) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
        end
        if (valid1_w) begin
          bits_total = bits_total + (rep1_w ? 1 : 7);
          if (rep1_w) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
        end
      end
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0; phantom_count = 0;
    bits_total = 0; addr_cyc = 0; bm_cyc = 0; repeat_hits = 0; new_hits = 0;
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
      if ((result_mask & ~pending) != 16'd0)
        phantom_count = phantom_count + popcount16(result_mask & ~pending);
      account_bits;

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
      account_bits;

      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);
      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;

      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d(%0d.%0d%%) acked=%0d phantom=%0d bits_total=%0d addr_cyc=%0d bm_cyc=%0d repeat_hits=%0d new_hits=%0d",
      trace_file_r, generated, overrun, (overrun*100)/generated, ((overrun*1000)/generated)%10,
      acked, phantom_count, bits_total, addr_cyc, bm_cyc, repeat_hits, new_hits);
    if (phantom_count == 0 && (acked == generated - overrun))
      $display("HYBRID3_TRACE_PASS %0s", trace_file_r);
    else
      $display("HYBRID3_TRACE_FAIL %0s phantom=%0d acked=%0d expected=%0d", trace_file_r, phantom_count, acked, generated-overrun);
    $fclose(fd);
    $finish;
  end
endmodule
