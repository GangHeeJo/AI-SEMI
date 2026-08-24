// cluster2_polarity를 진짜 UZH 극성 데이터(addrpol.txt: cycle addr_mask pol_mask)로 검증.
// 어드미션/타이밍 컨벤션은 검증된 tb_tristate_common_trace.v(§92에서 cluster2 662 overrun을
// 낸 바로 그 방식)와 정확히 동일하게 맞춤 -- "req 세팅 직후 즉시 읽기" 방식은 반복 오프셋이
// 생겨 overrun을 과소집계하는 버그가 있었음(46 vs 검증된 662), 이 파일에서 고침.
`timescale 1ns/1ps
module tb_cluster2_polarity_uzh_trace;
  parameter DRAIN_CYCLES = 3000;

  reg [1023:0] trace_file_r;
  reg clk = 0;
  reg rst;
  reg [15:0] req, polarity_in;

  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;
  aer_tx16_trad_rowcol_fovea_cluster2_polarity dut(
    .clk(clk), .rst(rst), .req(req), .polarity_in(polarity_in),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer cyc, c, i;
  integer generated, delivered, overrun, pol_mismatch;
  reg [15:0] pending, pending_pol, pending_clear_q, result_mask, ack_mask;

  function [3:0] rowbits4;
    input [15:0] v16; input [1:0] r;
    begin
      case (r)
        2'd0: rowbits4 = v16[3:0];
        2'd1: rowbits4 = v16[7:4];
        2'd2: rowbits4 = v16[11:8];
        default: rowbits4 = v16[15:12];
      endcase
    end
  endfunction

  reg [3:0] expect_pol0, expect_pol1;

  task automatic step_one_cycle;
    begin
      result_mask = 16'd0;
      expect_pol0 = rowbits4(polarity_in, r0);
      expect_pol1 = rowbits4(polarity_in, r1);
      if (v0) for (c = 0; c < 4; c = c + 1) if (cm0[c]) begin
        result_mask[r0*4+c] = 1'b1;
        if (pm0[c] !== expect_pol0[c]) begin
          pol_mismatch = pol_mismatch + 1;
          $display("POL_MISMATCH lane0 cyc=%0d row=%0d col=%0d", cyc, r0, c);
        end
      end
      if (v1) for (c = 0; c < 4; c = c + 1) if (cm1[c]) begin
        result_mask[r1*4+c] = 1'b1;
        if (pm1[c] !== expect_pol1[c]) begin
          pol_mismatch = pol_mismatch + 1;
          $display("POL_MISMATCH lane1 cyc=%0d row=%0d col=%0d", cyc, r1, c);
        end
      end
      ack_mask = result_mask & pending;
      delivered = delivered + $countones(ack_mask);
      req = pending & ~ack_mask;
      polarity_in = pending_pol;
      pending_clear_q = ack_mask;
    end
  endtask

  initial begin
    rst = 1; req = 16'd0; polarity_in = 16'd0;
    pending = 16'd0; pending_pol = 16'd0; pending_clear_q = 16'd0;
    generated = 0; delivered = 0; overrun = 0; pol_mismatch = 0;
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin $display("CANNOT_OPEN_TRACE %0s", trace_file_r); $finish; end
    scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);

    @(posedge clk); #1; rst = 0;

    cyc = 0;
    while (have_next) begin
      pending = pending & ~pending_clear_q;
      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) if (next_addr[i]) begin
          generated = generated + 1;
          if (pending[i]) overrun = overrun + 1;
          else begin
            pending[i] = 1'b1;
            pending_pol[i] = next_pol[i];
          end
        end
        scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      step_one_cycle;
      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~pending_clear_q;
      step_one_cycle;
      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d delivered=%0d overrun=%0d pol_mismatch=%0d",
      trace_file_r, generated, delivered, overrun, pol_mismatch);
    if (pol_mismatch == 0 && (delivered + overrun == generated)) $display("POLARITY_UZH_TRACE_PASS");
    else $display("POLARITY_UZH_TRACE_FAIL");
    $fclose(fd);
    $finish;
  end
endmodule
