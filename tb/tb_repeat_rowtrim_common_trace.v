// row-trim+repeat-flag 결합 코덱을 공식 50-workload trace로 검증 + 실제 비트절감 측정.
// 순정 cluster2 전용(row-trim 전제 때문). admission 순서는 §82 원칙(클리어를 새 도착
// 처리보다 먼저) 그대로. repeat 사이클엔 디코더 입력(row_bit/col_mask)을 0으로 지워
// 진짜 복원인지 확인.
`timescale 1ns/1ps
module tb_repeat_rowtrim_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  wire rep0_w, rep1_w, rowbit0_w, rowbit1_w;
  wire [31:0] bits_w;
  aer_cluster2_repeat_rowtrim_encode enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .repeat0(rep0_w), .repeat1(rep1_w), .row0_bit(rowbit0_w), .row1_bit(rowbit1_w),
    .bits_out(bits_w));

  wire link_rowbit0_in = rep0_w ? 1'b0 : rowbit0_w;
  wire [3:0] link_cm0_in  = rep0_w ? 4'd0 : colmask0_w;
  wire link_rowbit1_in = rep1_w ? 1'b0 : rowbit1_w;
  wire [3:0] link_cm1_in  = rep1_w ? 4'd0 : colmask1_w;

  wire [1:0] drow0, drow1; wire [3:0] dcm0, dcm1;
  aer_cluster2_repeat_rowtrim_decode dec(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .repeat0(rep0_w), .row0_bit_in(link_rowbit0_in), .col_mask0_in(link_cm0_in),
    .valid1(valid1_w), .repeat1(rep1_w), .row1_bit_in(link_rowbit1_in), .col_mask1_in(link_cm1_in),
    .row0_out(drow0), .col_mask0_out(dcm0), .row1_out(drow1), .col_mask1_out(dcm1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i, k;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked;
  integer native_bits, combo_bits, repeat_hits, decode_mismatch;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic step_and_check;
    begin
      result_mask = 16'd0;
      if (valid0_w) for (k = 0; k < 4; k = k + 1) if (colmask0_w[k]) result_mask[row0_w*4+k] = 1'b1;
      if (valid1_w) for (k = 0; k < 4; k = k + 1) if (colmask1_w[k]) result_mask[row1_w*4+k] = 1'b1;
      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);
      native_bits = native_bits + (valid0_w?7:0) + (valid1_w?7:0);
      combo_bits = combo_bits + bits_w;
      if (rep0_w) repeat_hits = repeat_hits + 1;
      if (rep1_w) repeat_hits = repeat_hits + 1;

      if (valid0_w && (drow0 !== row0_w || dcm0 !== colmask0_w)) decode_mismatch = decode_mismatch + 1;
      if (valid1_w && (drow1 !== row1_w || dcm1 !== colmask1_w)) decode_mismatch = decode_mismatch + 1;

      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0; native_bits = 0; combo_bits = 0;
    repeat_hits = 0; decode_mismatch = 0;
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
      step_and_check;
      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~pending_clear_q;
      step_and_check;
      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d acked=%0d native_bits=%0d combo_bits=%0d repeat_hits=%0d decode_mismatch=%0d",
      trace_file_r, generated, overrun, acked, native_bits, combo_bits, repeat_hits, decode_mismatch);
    if (decode_mismatch == 0 && acked == generated - overrun)
      $display("REPEAT_ROWTRIM_TRACE_PASS %0s", trace_file_r);
    else
      $display("REPEAT_ROWTRIM_TRACE_FAIL %0s", trace_file_r);
    $fclose(fd);
    $finish;
  end
endmodule
