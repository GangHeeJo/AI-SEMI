// "3단 결합(raw+EF+bitmap)이 실효가 있냐"를 §71과 똑같은 방식으로 검증: 공식
// 50-workload trace를 그대로 흘려서, cluster2(주소기반, admission-limited, 실제 RTL)와
// tristate(위치기반류, 무제한용량 -- pending 전부를 그 사이클에 즉시 배달)를 독립
// scoreboard로 나란히 돌려 실측 총 비트를 비교한다. §69/§78의 K-밀도 합성 스윕과 달리
// 실제 트래픽 분포를 그대로 쓴다는 게 이번 검증의 핵심(§71에서 합성 스윕 낙관치가
// 실제 워크로드에서 재현 안 된 전례가 있어서).
`timescale 1ns/1ps
module tb_tristate_common_trace;
  parameter DRAIN_CYCLES = 3000;
  parameter ADDR_BITS_PER_GRANT = 7; // valid(1)+row(2)+col_mask(4), cluster2 native
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

  // tristate 3단 인코더 -- pending2 전체 집합을 매 사이클 조합논리로 그대로 먹임
  reg [6:0] batch_count_t;
  reg [16*4-1:0] batch_sources_t; // MAX_BATCH=16, ADDRESS_WIDTH=4
  wire [1:0] mode_w2;
  wire [31:0] total_bits_w2;
  wire input_error_w2;
  wire [31:0] raw_dbg_w2, ef_dbg_w2;

  a6_tristate_raw_ef_bitmap #(.NUM_SOURCES(16), .MAX_BATCH(16), .ADDRESS_WIDTH(4), .COUNT_WIDTH(5))
    tri_inst(.batch_count(batch_count_t), .batch_sources(batch_sources_t),
        .mode_out(mode_w2), .total_bits_out(total_bits_w2), .input_error(input_error_w2),
        .raw_bits_dbg(raw_dbg_w2), .ef_bits_dbg(ef_dbg_w2));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i, k;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] pending2;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked;
  integer c2_bits;
  integer generated2, overrun2, acked2, tri_bits, tri_cycles;

  function automatic integer popcount16;
    input [15:0] bits;
    integer bi;
    begin
      popcount16 = 0;
      for (bi = 0; bi < 16; bi = bi + 1) if (bits[bi]) popcount16 = popcount16 + 1;
    end
  endfunction

  task automatic drive_tristate_from_pending2;
    integer n, s4;
    begin
      n = 0;
      batch_sources_t = {(16*4){1'b0}};
      for (s4 = 0; s4 < 16; s4 = s4 + 1) begin
        if (pending2[s4]) begin
          batch_sources_t[n*4 +: 4] = s4[3:0];
          n = n + 1;
        end
      end
      batch_count_t = n[6:0];
    end
  endtask

  task automatic step_one_cycle;
    begin
      // --- cluster2 (native, admission-limited) --- (pending 클리어는 호출부에서 선행)
      result_mask = 16'd0;
      if (valid0_w) for (k = 0; k < 4; k = k + 1) if (colmask0_w[k]) result_mask[row0_w*4+k] = 1'b1;
      if (valid1_w) for (k = 0; k < 4; k = k + 1) if (colmask1_w[k]) result_mask[row1_w*4+k] = 1'b1;
      ack_mask = result_mask & pending;
      acked = acked + popcount16(ack_mask);
      c2_bits = c2_bits + (valid0_w ? ADDR_BITS_PER_GRANT : 0) + (valid1_w ? ADDR_BITS_PER_GRANT : 0);
      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;

      // --- tristate (unlimited capacity, 매 사이클 pending2 전부 즉시 배달) ---
      drive_tristate_from_pending2;
      #1;
      if (pending2 != 16'd0) begin
        if (!input_error_w2) begin
          tri_bits = tri_bits + total_bits_w2;
          tri_cycles = tri_cycles + 1;
        end
        acked2 = acked2 + popcount16(pending2);
        pending2 = 16'd0;
      end
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0; c2_bits = 0;
    generated2 = 0; overrun2 = 0; acked2 = 0; tri_bits = 0; tri_cycles = 0;
    pending = 16'd0; pending_clear_q = 16'd0; pending2 = 16'd0;
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
            generated2 = generated2 + 1;
            if (pending2[i]) overrun2 = overrun2 + 1; else pending2[i] = 1'b1;
          end
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
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

    $display("TRACE=%0s generated=%0d C2_bits=%0d C2_overrun=%0d TRI_bits=%0d TRI_overrun=%0d TRI_cycles=%0d",
      trace_file_r, generated, c2_bits, overrun, tri_bits, overrun2, tri_cycles);
    $fclose(fd);
    $finish;
  end
endmodule
