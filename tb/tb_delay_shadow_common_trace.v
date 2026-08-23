// Delay-Shadow AER를 공식 50-workload trace로 검증. 매 배달 이벤트마다 "진짜 발생
// 사이클"을 소스별로 추적해뒀다가, q로 복원한 occurrence cycle과 정확히 일치하는지
// **이벤트 단위로**(row 단위가 아니라) 전수 확인 -- 한 grant(row+col_mask)가 여러 열을
// 동시에 담을 때, 그 열들이 서로 다른 사이클에 도착했었다면 delay-shadow의 row단위 q
// 하나로 전부 정확히 복원되는지가 이 검증의 핵심 질문.
`timescale 1ns/1ps
module tb_delay_shadow_common_trace;
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

  wire ov0, ov1; wire [1:0] pr0, pr1; wire [3:0] ocm0, ocm1;
  aer_cluster2_delay_shadow_encode enc(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .out_valid0(ov0), .packed_row0(pr0), .out_col_mask0(ocm0),
    .out_valid1(ov1), .packed_row1(pr1), .out_col_mask1(ocm1));

  wire dv0, dv1; wire [1:0] drow0, drow1; wire dq0, dq1;
  aer_cluster2_delay_shadow_decode dec(
    .in_valid0(ov0), .packed_row0(pr0),
    .in_valid1(ov1), .packed_row1(pr1),
    .valid0(dv0), .row0(drow0), .q0(dq0),
    .valid1(dv1), .row1(drow1), .q1(dq1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i, k, dcyc;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked;
  integer decode_mismatch, ts_mismatch, ts_checked;
  integer occ_cycle [0:15]; // 소스별 "진짜 발생(admission) 사이클"

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic check_lane;
    input integer valid_in;
    input integer native_row;
    input [3:0] native_cm;
    input integer dec_valid;
    input integer dec_row;
    input integer dec_q;
    input [3:0] dec_cm;
    integer c2, src, recon_occ;
    begin
      if (valid_in) begin
        // 주소(round-trip) 정확성
        if (!dec_valid || dec_row !== native_row || dec_cm !== native_cm)
          decode_mismatch = decode_mismatch + 1;
        // 타임스탬프 복원 정확성: 이 grant가 담은 열마다(개별 이벤트 단위) 검증
        for (c2 = 0; c2 < 4; c2 = c2 + 1) begin
          if (native_cm[c2]) begin
            src = native_row*4 + c2;
            recon_occ = cyc - dec_q;
            ts_checked = ts_checked + 1;
            if (recon_occ !== occ_cycle[src]) ts_mismatch = ts_mismatch + 1;
          end
        end
      end
    end
  endtask

  task automatic step_and_check;
    begin
      result_mask = 16'd0;
      if (valid0_w) for (k = 0; k < 4; k = k + 1) if (colmask0_w[k]) result_mask[row0_w*4+k] = 1'b1;
      if (valid1_w) for (k = 0; k < 4; k = k + 1) if (colmask1_w[k]) result_mask[row1_w*4+k] = 1'b1;
      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);

      check_lane(valid0_w, row0_w, colmask0_w, dv0, drow0, dq0, ocm0);
      check_lane(valid1_w, row1_w, colmask1_w, dv1, drow1, dq1, ocm1);

      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0;
    decode_mismatch = 0; ts_mismatch = 0; ts_checked = 0;
    pending = 16'd0; pending_clear_q = 16'd0;
    for (i = 0; i < 16; i = i + 1) occ_cycle[i] = -1;
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
            if (pending[i]) overrun = overrun + 1;
            else begin pending[i] = 1'b1; occ_cycle[i] = cyc; end
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end
      step_and_check;
      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (dcyc = 0; dcyc < DRAIN_CYCLES; dcyc = dcyc + 1) begin
      pending = pending & ~pending_clear_q;
      step_and_check;
      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    $display("TRACE=%0s generated=%0d overrun=%0d acked=%0d decode_mismatch=%0d ts_checked=%0d ts_mismatch=%0d",
      trace_file_r, generated, overrun, acked, decode_mismatch, ts_checked, ts_mismatch);
    if (decode_mismatch == 0 && ts_mismatch == 0 && acked == generated - overrun)
      $display("DELAY_SHADOW_TRACE_PASS %0s", trace_file_r);
    else
      $display("DELAY_SHADOW_TRACE_FAIL %0s", trace_file_r);
    $fclose(fd);
    $finish;
  end
endmodule
