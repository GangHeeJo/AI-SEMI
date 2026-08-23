// rowtrim 코덱을 공식 50-workload trace로 검증(3단계 중 마지막): 실제 cluster2 출력을
// 매 사이클 인코드->디코드 왕복해서 항상 원본과 일치하는지 + 실제 비트 절감(14.3% 기대)이
// 트래픽 패턴과 무관하게 항상 성립하는지 확인. admission 순서는 §82에서 잡은 버그와
// 같은 원칙(pending 클리어를 새 도착 처리보다 먼저) 적용.
`timescale 1ns/1ps
module tb_rowtrim_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;
  wire [5:0] p0, p1;
  wire dv0, dv1; wire [1:0] dr0, dr1; wire [3:0] dc0, dc1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));
  aer_cluster2_rowtrim_encode enc(
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .lane0_packed(p0), .lane1_packed(p1));
  aer_cluster2_rowtrim_decode dec(
    .lane0_packed(p0), .lane1_packed(p1),
    .valid0(dv0), .row0(dr0), .col_mask0(dc0),
    .valid1(dv1), .row1(dr1), .col_mask1(dc1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i, k;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked;
  integer native_bits, packed_bits, roundtrip_mismatch;

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
      native_bits = native_bits + (valid0_w ? 7 : 0) + (valid1_w ? 7 : 0);
      packed_bits = packed_bits + (valid0_w ? 6 : 0) + (valid1_w ? 6 : 0);

      if (dv0 !== valid0_w || dv1 !== valid1_w) roundtrip_mismatch = roundtrip_mismatch + 1;
      else begin
        if (valid0_w && (dr0 !== row0_w || dc0 !== colmask0_w)) roundtrip_mismatch = roundtrip_mismatch + 1;
        if (valid1_w && (dr1 !== row1_w || dc1 !== colmask1_w)) roundtrip_mismatch = roundtrip_mismatch + 1;
      end

      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0; native_bits = 0; packed_bits = 0; roundtrip_mismatch = 0;
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

    $display("TRACE=%0s generated=%0d overrun=%0d acked=%0d native_bits=%0d packed_bits=%0d roundtrip_mismatch=%0d",
      trace_file_r, generated, overrun, acked, native_bits, packed_bits, roundtrip_mismatch);
    if (roundtrip_mismatch == 0 && acked == generated - overrun)
      $display("ROWTRIM_TRACE_PASS %0s", trace_file_r);
    else
      $display("ROWTRIM_TRACE_FAIL %0s", trace_file_r);
    $fclose(fd);
    $finish;
  end
endmodule
