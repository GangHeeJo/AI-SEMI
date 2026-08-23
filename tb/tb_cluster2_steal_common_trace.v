// cluster2 vs cluster2_steal을 준영 공용 trace로 비교 -- 준영의 실제 바인딩
// (aer_ganghee_cluster2_binding.sv, 읽기만 함, 손대지 않음)의 정확한 배선을 그대로
// 재구현: native_ack_mask = result_mask & pending(같은 사이클, 조합논리로 즉시 억제),
// native_req = pending & ~ack_mask(같은 사이클 재구동 방지), pending 자체의 클리어는
// aer_clean_tb.sv의 `pending[..] <= 1'b0`가 논블로킹이라 1사이클 늦게 보임. 4연속
// 재발화(1사이클 간격)로 손으로 검증: admit,overrun,admit,overrun = 정확히 50% --
// 준영 공식 결과(retrigger_identity/affine 둘 다 50.00%)와 일치함.
`timescale 1ns/1ps
module tb_cluster2_steal_common_trace;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req_f, req_s;
  wire valid0_f; wire [1:0] row0_f; wire [3:0] colmask0_f;
  wire valid1_f; wire [1:0] row1_f; wire [3:0] colmask1_f;
  wire valid0_s; wire [1:0] row0_s; wire [3:0] colmask0_s;
  wire valid1_s; wire [1:0] row1_s; wire [3:0] colmask1_s;

  aer_tx16_trad_rowcol_fovea_cluster2 tx_fixed(
    .clk(clk), .rst(rst), .req(req_f),
    .valid0(valid0_f), .row0(row0_f), .col_mask0(colmask0_f),
    .valid1(valid1_f), .row1(row1_f), .col_mask1(colmask1_f));
  aer_tx16_trad_rowcol_fovea_cluster2_steal tx_steal(
    .clk(clk), .rst(rst), .req(req_s),
    .valid0(valid0_s), .row0(row0_s), .col_mask0(colmask0_s),
    .valid1(valid1_s), .row1(row1_s), .col_mask1(colmask1_s));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, c, i;
  reg [15:0] pending_f, pending_s;
  reg [15:0] pending_clear_f_q, pending_clear_s_q; // 논블로킹 지연 재현(1단)
  reg [15:0] result_mask_f, result_mask_s;
  reg [15:0] ack_mask_f, ack_mask_s;
  integer generated, overrun_f, overrun_s, acked_f, acked_s;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic decode_result(
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
    generated = 0; overrun_f = 0; overrun_s = 0; acked_f = 0; acked_s = 0;
    pending_f = 16'd0; pending_s = 16'd0;
    pending_clear_f_q = 16'd0; pending_clear_s_q = 16'd0;
    rst = 1; req_f = 16'd0; req_s = 16'd0;
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
      // 1) 지난 사이클에 ack된 것(논블로킹으로 스케줄된 것)을 이제 반영.
      pending_f = pending_f & ~pending_clear_f_q;
      pending_s = pending_s & ~pending_clear_s_q;

      // 2) 새 도착 처리(이번 사이클, 블로킹처럼 즉시) -- pending이면 overrun.
      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) begin
          if (next_mask[i]) begin
            generated = generated + 1;
            if (pending_f[i]) overrun_f = overrun_f + 1; else pending_f[i] = 1'b1;
            if (pending_s[i]) overrun_s = overrun_s + 1; else pending_s[i] = 1'b1;
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end

      // 3) 현재 DUT 출력(직전 edge 결과)으로 result_mask 계산.
      decode_result(valid0_f, row0_f, colmask0_f, valid1_f, row1_f, colmask1_f, result_mask_f);
      decode_result(valid0_s, row0_s, colmask0_s, valid1_s, row1_s, colmask1_s, result_mask_s);

      // 4) ack_mask = result_mask & pending(같은 사이클, 조합논리) -- 재구동 방지.
      ack_mask_f = result_mask_f & pending_f;
      ack_mask_s = result_mask_s & pending_s;
      acked_f = acked_f + popcount16(ack_mask_f);
      acked_s = acked_s + popcount16(ack_mask_s);

      // 5) req는 이번 사이클에 즉시 ack_mask를 빼고 구동(같은 사이클 재요청 억제).
      req_f = pending_f & ~ack_mask_f;
      req_s = pending_s & ~ack_mask_s;

      // 6) pending의 실제 클리어는 논블로킹이라 다음 사이클에야 보임(1)에서 반영).
      pending_clear_f_q = ack_mask_f;
      pending_clear_s_q = ack_mask_s;

      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending_f = pending_f & ~pending_clear_f_q;
      pending_s = pending_s & ~pending_clear_s_q;

      decode_result(valid0_f, row0_f, colmask0_f, valid1_f, row1_f, colmask1_f, result_mask_f);
      decode_result(valid0_s, row0_s, colmask0_s, valid1_s, row1_s, colmask1_s, result_mask_s);
      ack_mask_f = result_mask_f & pending_f;
      ack_mask_s = result_mask_s & pending_s;
      acked_f = acked_f + popcount16(ack_mask_f);
      acked_s = acked_s + popcount16(ack_mask_s);

      req_f = pending_f & ~ack_mask_f;
      req_s = pending_s & ~ack_mask_s;
      pending_clear_f_q = ack_mask_f;
      pending_clear_s_q = ack_mask_s;

      @(posedge clk); #1;
    end

    $display("TRACE=%0s generated=%0d", trace_file_r, generated);
    $display("[cluster2]       overrun=%0d(%0d.%0d%%) acked=%0d  accepted_check=%0d",
      overrun_f, (overrun_f*100)/generated, ((overrun_f*1000)/generated)%10, acked_f, generated-overrun_f);
    $display("[cluster2_steal] overrun=%0d(%0d.%0d%%) acked=%0d  accepted_check=%0d",
      overrun_s, (overrun_s*100)/generated, ((overrun_s*1000)/generated)%10, acked_s, generated-overrun_s);
    $fclose(fd);
    $finish;
  end
endmodule
