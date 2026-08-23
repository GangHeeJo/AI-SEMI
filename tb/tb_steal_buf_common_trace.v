// cluster2_steal_buf를 준영의 공용 공개 trace(manifest.multilane-n16.json에서
// generate_trace.py로 직접 생성, 우리 repo 안에서 변환한 cyclemask.txt)로 직접 구동.
// 공용 TB(aer_clean_tb.sv)를 거치지 않음 -- 그 TB는 소스당 1-entry pending 게이트가
// 있어서 이 결합판의 2-deep 버퍼 이점을 애초에 못 봄(progress.md §58 정정 참고).
// 여기선 trace의 원시 occurrence를 그대로(억제 없이) arrival 펄스로 흘려보내고,
// 결합판 자신의 overrun 출력으로 손실을 판정 -- 결합판의 native 2-deep 계약에 맞는
// 공정한 방식(manifest 자체가 "logical event"만 고정하고 admission은 후보 native
// capability에 맡긴다고 명시함).
`timescale 1ns/1ps
module tb_steal_buf_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer fd;
  integer scan_ret;
  integer next_cycle;
  integer next_mask;
  integer have_next;
  integer cyc;
  integer generated, overrun_count, delivered;
  integer c;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1)
        if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1)
          if (mask_in[c]) delivered = delivered + 1;
      end
    end
  endtask

  initial begin
    generated = 0; overrun_count = 0; delivered = 0;
    rst = 1; arrival = 16'd0;
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin
      $display("CANNOT_OPEN_TRACE %0s", trace_file_r);
      $finish;
    end
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
      overrun_count = overrun_count + popcount16(overrun);
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
      cyc = cyc + 1;
    end

    arrival = 16'd0;
    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
    end

    $display("TRACE=%0s generated=%0d overrun=%0d accepted=%0d delivered=%0d overrun_ratio_x1000=%0d",
      trace_file_r, generated, overrun_count, generated - overrun_count, delivered,
      (generated == 0) ? 0 : (overrun_count * 1000) / generated);

    if (generated - overrun_count != delivered)
      $display("COUNT_MISMATCH accepted=%0d delivered=%0d", generated - overrun_count, delivered);
    else
      $display("STEAL_BUF_TRACE_CONSISTENT");

    $fclose(fd);
    $finish;
  end
endmodule
