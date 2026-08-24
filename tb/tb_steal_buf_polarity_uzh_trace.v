// cluster2_steal_buf_polarity를 진짜 UZH 극성 데이터(addrpol.txt)로 검증. arrival은
// 트레이스의 그 사이클 비트를 그대로 펄스로 넣음(steal_buf는 pending_cnt를 자체적으로
// 들고 있어서 TB가 별도 admission 모델을 안 돌려도 됨 -- §93/phantom_debug와 동일 패턴).
`timescale 1ns/1ps
module tb_steal_buf_polarity_uzh_trace;
  reg [1023:0] trace_file_r;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;

  wire [15:0] ov;
  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer c, i, cyc, drain_until;
  integer generated, delivered, dropped_overrun, pol_mismatch, checked_pol_bits;
  reg [15:0] ov_sample;
  reg [1:0] shadow_depth [0:15];
  reg pol_shadow0 [0:15];
  reg pol_shadow1 [0:15];

  task automatic shadow_check_grant(input integer valid_in, input integer row_in, input [3:0] mask_in, input [3:0] polmask_in);
    integer idx;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) if (mask_in[c]) begin
          idx = row_in*4 + c;
          delivered = delivered + 1;
          checked_pol_bits = checked_pol_bits + 1;
          if (shadow_depth[idx] == 2'd0) begin
            $display("SHADOW_EMPTY_ON_GRANT idx=%0d cyc=%0d", idx, cyc);
          end else begin
            if (polmask_in[c] !== pol_shadow0[idx]) begin
              pol_mismatch = pol_mismatch + 1;
              $display("POL_FIFO_MISMATCH idx=%0d cyc=%0d got=%b want=%b", idx, cyc, polmask_in[c], pol_shadow0[idx]);
            end
            pol_shadow0[idx] = pol_shadow1[idx];
            shadow_depth[idx] = shadow_depth[idx] - 2'd1;
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; pol_mismatch = 0; checked_pol_bits = 0;
    for (i = 0; i < 16; i = i + 1) begin
      shadow_depth[i] = 2'd0; pol_shadow0[i] = 1'b0; pol_shadow1[i] = 1'b0;
    end
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
      arrival = 16'd0; polarity_in = 16'd0;
      if (have_next && next_cycle == cyc) begin
        arrival = next_addr[15:0];
        polarity_in = next_pol[15:0];
        for (i = 0; i < 16; i = i + 1) if (arrival[i]) generated = generated + 1;
        scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      #1;
      ov_sample = ov;
      for (i = 0; i < 16; i = i + 1) if (ov_sample[i]) dropped_overrun = dropped_overrun + 1;

      @(posedge clk); #1;

      shadow_check_grant(v0, r0, cm0, pm0);
      shadow_check_grant(v1, r1, cm1, pm1);

      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && !ov_sample[i]) begin
          if (shadow_depth[i] == 2'd0) pol_shadow0[i] = polarity_in[i];
          else pol_shadow1[i] = polarity_in[i];
          shadow_depth[i] = shadow_depth[i] + 2'd1;
        end
      end

      cyc = cyc + 1;
    end

    arrival = 16'd0; polarity_in = 16'd0;
    drain_until = cyc + 15000;
    for (cyc = cyc; cyc < drain_until; cyc = cyc + 1) begin
      @(posedge clk); #1;
      shadow_check_grant(v0, r0, cm0, pm0);
      shadow_check_grant(v1, r1, cm1, pm1);
    end

    for (i = 0; i < 16; i = i + 1) if (shadow_depth[i] != 0) begin
      $display("DRAIN_INCOMPLETE idx=%0d depth=%0d", i, shadow_depth[i]);
      pol_mismatch = pol_mismatch + 1;
    end
    if (generated != delivered + dropped_overrun) begin
      $display("COUNT_MISMATCH generated=%0d delivered=%0d dropped=%0d", generated, delivered, dropped_overrun);
      pol_mismatch = pol_mismatch + 1;
    end

    $display("TRACE=%0s generated=%0d delivered=%0d dropped_overrun=%0d checked_pol_bits=%0d pol_mismatch=%0d",
      trace_file_r, generated, delivered, dropped_overrun, checked_pol_bits, pol_mismatch);
    if (pol_mismatch == 0) $display("STEAL_BUF_POLARITY_UZH_PASS");
    else $display("STEAL_BUF_POLARITY_UZH_FAIL");
    $fclose(fd);
    $finish;
  end
endmodule
