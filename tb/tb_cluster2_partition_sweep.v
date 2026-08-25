// row-partition 스윕: cluster2가 4개 행을 2개씩 묶는 방식은 {0,3}/{1,2}(현재 채택,
// partition C) 말고도 {0,1}/{2,3}(A), {0,2}/{1,3}(B) 두 가지가 더 있음 -- 세 후보 전부
// 원본 로직은 무수정이고 CENTER_MASK/PERIPH_MASK 상수만 다름(idx4가 행 인덱스를 일반적으로
// 처리해서 다른 코드 변경 불필요, 실제 diff로 확인함). 어느 파티션이 공식 워크로드에서
// 손실을 더 줄이는지 컴파일타임 매크로(PART_A/PART_B, 둘 다 없으면 C)로 골라서 잼.
// admission 모델은 §92부터 써온 검증된 방식(pending & ~pending_clear_q, req=pending&~ack).
`timescale 1ns/1ps
module tb_cluster2_partition_sweep;
  parameter DRAIN_CYCLES = 3000;
  reg [1023:0] trace_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

`ifdef PART_A
  aer_tx16_trad_rowcol_fovea_cluster2_partA dut(
`elsif PART_B
  aer_tx16_trad_rowcol_fovea_cluster2_partB dut(
`else
  aer_tx16_trad_rowcol_fovea_cluster2 dut(
`endif
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  always #5 clk = ~clk;

  integer fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, i, k;
  reg [15:0] pending, pending_clear_q;
  reg [15:0] result_mask, ack_mask;
  integer generated, overrun, acked;

  task automatic step_one_cycle;
    begin
      result_mask = 16'd0;
      if (valid0_w) for (k = 0; k < 4; k = k + 1) if (colmask0_w[k]) result_mask[row0_w*4+k] = 1'b1;
      if (valid1_w) for (k = 0; k < 4; k = k + 1) if (colmask1_w[k]) result_mask[row1_w*4+k] = 1'b1;
      ack_mask = result_mask & pending;
      acked = acked + $countones(ack_mask);
      req = pending & ~ack_mask;
      pending_clear_q = ack_mask;
    end
  endtask

  initial begin
    generated = 0; overrun = 0; acked = 0;
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
      step_one_cycle;
      @(posedge clk); #1;
      cyc = cyc + 1;
    end

    for (cyc = 0; cyc < DRAIN_CYCLES; cyc = cyc + 1) begin
      pending = pending & ~pending_clear_q;
      step_one_cycle;
      @(posedge clk); #1;
    end

    if (generated - overrun != acked) begin
      $display("COUNT_MISMATCH generated=%0d overrun=%0d acked=%0d", generated, overrun, acked);
    end
    $display("TRACE=%0s generated=%0d overrun=%0d acked=%0d", trace_file_r, generated, overrun, acked);
    $fclose(fd);
    $finish;
  end
endmodule
