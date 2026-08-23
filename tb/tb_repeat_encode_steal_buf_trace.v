// repeat-flag 코덱 + cluster2_steal_buf를 공식 50-workload trace로 검증 -- 실제 최종
// 후보에 얹었을 때의 진짜 비트절감·정확성. §87(row-trim은 steal_buf에 안 됨)과 달리
// repeat-flag는 row 값 범위에 의존하지 않으므로 안전할 것이라는 §(리벤지) 가설을
// 공식 trace로 최종 확인.
`timescale 1ns/1ps
module tb_repeat_encode_steal_buf_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  wire rep0_w, rep1_w;
  wire [31:0] bits_w;
  aer_cluster2_repeat_encode enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .repeat0(rep0_w), .repeat1(rep1_w), .bits_out(bits_w));

  wire [1:0] link_row0_in = rep0_w ? 2'd0 : row0_w;
  wire [3:0] link_cm0_in  = rep0_w ? 4'd0 : colmask0_w;
  wire [1:0] link_row1_in = rep1_w ? 2'd0 : row1_w;
  wire [3:0] link_cm1_in  = rep1_w ? 4'd0 : colmask1_w;

  wire [1:0] drow0, drow1; wire [3:0] dcm0, dcm1;
  aer_cluster2_repeat_decode dec(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .repeat0(rep0_w), .row0_in(link_row0_in), .col_mask0_in(link_cm0_in),
    .valid1(valid1_w), .repeat1(rep1_w), .row1_in(link_row1_in), .col_mask1_in(link_cm1_in),
    .row0_out(drow0), .col_mask0_out(dcm0), .row1_out(drow1), .col_mask1_out(dcm1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, c;
  integer generated, overrun_count, delivered;
  integer native_bits, repeat_bits, repeat_hits, decode_mismatch;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic drain_and_check;
    begin
      overrun_count = overrun_count + popcount16(overrun_w);
      if (valid0_w) for (c = 0; c < 4; c = c + 1) if (colmask0_w[c]) delivered = delivered + 1;
      if (valid1_w) for (c = 0; c < 4; c = c + 1) if (colmask1_w[c]) delivered = delivered + 1;

      native_bits = native_bits + (valid0_w?7:0) + (valid1_w?7:0);
      repeat_bits = repeat_bits + bits_w;
      if (rep0_w) repeat_hits = repeat_hits + 1;
      if (rep1_w) repeat_hits = repeat_hits + 1;
      if (valid0_w && (drow0 !== row0_w || dcm0 !== colmask0_w)) decode_mismatch = decode_mismatch + 1;
      if (valid1_w && (drow1 !== row1_w || dcm1 !== colmask1_w)) decode_mismatch = decode_mismatch + 1;
    end
  endtask

  initial begin
    generated = 0; overrun_count = 0; delivered = 0;
    native_bits = 0; repeat_bits = 0; repeat_hits = 0; decode_mismatch = 0;
    rst = 1; arrival = 16'd0;
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
      arrival = 16'd0;
      while (have_next && next_cycle == cyc) begin
        arrival = arrival | next_mask[15:0];
        generated = generated + popcount16(next_mask[15:0]);
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end
      @(posedge clk); #1;
      drain_and_check;
      cyc = cyc + 1;
    end

    arrival = 16'd0;
    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain_and_check;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d delivered=%0d native_bits=%0d repeat_bits=%0d repeat_hits=%0d decode_mismatch=%0d",
      trace_file_r, generated, overrun_count, delivered, native_bits, repeat_bits, repeat_hits, decode_mismatch);
    if (decode_mismatch == 0 && (generated - overrun_count == delivered))
      $display("REPEAT_STEAL_BUF_TRACE_PASS %0s", trace_file_r);
    else
      $display("REPEAT_STEAL_BUF_TRACE_FAIL %0s", trace_file_r);
    $fclose(fd);
    $finish;
  end
endmodule
