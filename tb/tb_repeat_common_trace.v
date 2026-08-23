// cluster2+repeat압축 vs cluster2 순정을 준영 공용 trace로 나란히 비교 -- 배선은
// tb_cluster2_steal_common_trace.v와 동일(native_ack_mask/native_req/논블로킹 지연).
// 비트비용: 순정=그랜트당 6b(row2+colmask4) 고정. repeat판=그랜트당 flag(1b)+
// (repeat면 0b, 아니면 row2+colmask4=6b) = repeat 1b 또는 new 7b.
`timescale 1ns/1ps
module tb_repeat_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req_f, req_r;
  wire valid0_f; wire [1:0] row0_f; wire [3:0] colmask0_f;
  wire valid1_f; wire [1:0] row1_f; wire [3:0] colmask1_f;
  wire valid0_r; wire [1:0] row0_r; wire [3:0] colmask0_r; wire rep0_r;
  wire valid1_r; wire [1:0] row1_r; wire [3:0] colmask1_r; wire rep1_r;

  aer_tx16_trad_rowcol_fovea_cluster2 tx_plain(
    .clk(clk), .rst(rst), .req(req_f),
    .valid0(valid0_f), .row0(row0_f), .col_mask0(colmask0_f),
    .valid1(valid1_f), .row1(row1_f), .col_mask1(colmask1_f));
  aer_tx16_trad_rowcol_fovea_cluster2_repeat tx_repeat(
    .clk(clk), .rst(rst), .req(req_r),
    .valid0(valid0_r), .row0(row0_r), .col_mask0(colmask0_r), .repeat0(rep0_r),
    .valid1(valid1_r), .row1(row1_r), .col_mask1(colmask1_r), .repeat1(rep1_r));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i;
  reg [15:0] pending_f, pending_r;
  reg [15:0] pending_clear_f_q, pending_clear_r_q;
  reg [15:0] result_mask_f, result_mask_r;
  reg [15:0] ack_mask_f, ack_mask_r;
  integer generated, overrun_f, overrun_r, acked_f, acked_r;
  integer bits_plain, bits_repeat, repeat_hits, new_hits;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic decode_plain(
    input integer v0, input integer r0, input [3:0] cm0,
    input integer v1, input integer r1, input [3:0] cm1,
    output reg [15:0] rmask);
    integer k;
    begin
      rmask = 16'd0;
      if (v0) for (k = 0; k < 4; k = k + 1) if (cm0[k]) rmask[r0*4+k] = 1'b1;
      if (v1) for (k = 0; k < 4; k = k + 1) if (cm1[k]) rmask[r1*4+k] = 1'b1;
    end
  endtask

  initial begin
    generated = 0; overrun_f = 0; overrun_r = 0; acked_f = 0; acked_r = 0;
    bits_plain = 0; bits_repeat = 0; repeat_hits = 0; new_hits = 0;
    pending_f = 16'd0; pending_r = 16'd0;
    pending_clear_f_q = 16'd0; pending_clear_r_q = 16'd0;
    rst = 1; req_f = 16'd0; req_r = 16'd0;
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
      pending_f = pending_f & ~pending_clear_f_q;
      pending_r = pending_r & ~pending_clear_r_q;

      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) begin
          if (next_mask[i]) begin
            generated = generated + 1;
            if (pending_f[i]) overrun_f = overrun_f + 1; else pending_f[i] = 1'b1;
            if (pending_r[i]) overrun_r = overrun_r + 1; else pending_r[i] = 1'b1;
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end

      decode_plain(valid0_f, row0_f, colmask0_f, valid1_f, row1_f, colmask1_f, result_mask_f);
      decode_plain(valid0_r, row0_r, colmask0_r, valid1_r, row1_r, colmask1_r, result_mask_r);

      ack_mask_f = result_mask_f & pending_f;
      ack_mask_r = result_mask_r & pending_r;
      acked_f = acked_f + popcount16(ack_mask_f);
      acked_r = acked_r + popcount16(ack_mask_r);

      if (valid0_f) bits_plain = bits_plain + 6;
      if (valid1_f) bits_plain = bits_plain + 6;
      if (valid0_r) begin
        bits_repeat = bits_repeat + (rep0_r ? 1 : 7);
        if (rep0_r) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
      end
      if (valid1_r) begin
        bits_repeat = bits_repeat + (rep1_r ? 1 : 7);
        if (rep1_r) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
      end

      req_f = pending_f & ~ack_mask_f;
      req_r = pending_r & ~ack_mask_r;

      pending_clear_f_q = ack_mask_f;
      pending_clear_r_q = ack_mask_r;

      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending_f = pending_f & ~pending_clear_f_q;
      pending_r = pending_r & ~pending_clear_r_q;

      decode_plain(valid0_f, row0_f, colmask0_f, valid1_f, row1_f, colmask1_f, result_mask_f);
      decode_plain(valid0_r, row0_r, colmask0_r, valid1_r, row1_r, colmask1_r, result_mask_r);
      ack_mask_f = result_mask_f & pending_f;
      ack_mask_r = result_mask_r & pending_r;
      acked_f = acked_f + popcount16(ack_mask_f);
      acked_r = acked_r + popcount16(ack_mask_r);

      if (valid0_f) bits_plain = bits_plain + 6;
      if (valid1_f) bits_plain = bits_plain + 6;
      if (valid0_r) begin
        bits_repeat = bits_repeat + (rep0_r ? 1 : 7);
        if (rep0_r) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
      end
      if (valid1_r) begin
        bits_repeat = bits_repeat + (rep1_r ? 1 : 7);
        if (rep1_r) repeat_hits = repeat_hits + 1; else new_hits = new_hits + 1;
      end

      req_f = pending_f & ~ack_mask_f;
      req_r = pending_r & ~ack_mask_r;
      pending_clear_f_q = ack_mask_f;
      pending_clear_r_q = ack_mask_r;

      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d overrun_f=%0d overrun_r=%0d acked_f=%0d acked_r=%0d bits_plain=%0d bits_repeat=%0d repeat_hits=%0d new_hits=%0d",
      trace_file_r, generated, overrun_f, overrun_r, acked_f, acked_r, bits_plain, bits_repeat, repeat_hits, new_hits);
    $fclose(fd);
    $finish;
  end
endmodule
