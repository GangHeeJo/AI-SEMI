`timescale 1ns/1ps
// rtl/bayes_filter.v를 scripts/dump_bayes_filter_vectors.py가 만든 실제 UZH 이벤트 벡터
// (row col pol map_theta_expected)로 검증 -- RTL의 매 이벤트 MAP theta가 정수 고정소수점
// 오라클(run_bayes_filter_fixed(), §131/132 확정 파라미터 eps_shift=8/alpha=2)과 한 비트도
// 안 틀리고 일치하는지 확인한다. 이벤트는 busy가 내려간 뒤(즉 이전 이벤트의 valid_out까지
// 끝난 뒤) 하나씩 순차로 넣는다 -- predictor는 원래 전역 상태를 순서대로 갱신하는 직렬 필터라
// 파이프라이닝하지 않음(rtl/bayes_filter.v 헤더 코멘트 참고).
// §134부터 world memory가 모듈 밖 SRAM(tb/sync_sram_1rw.v, 1-cycle latency)으로 분리됨.
module tb_bayes_filter_uzh_trace;
  localparam N_THETA_BITS = 10;
  localparam COORD_BITS   = 10;

  reg clk = 0;
  reg rst;
  reg valid_in;
  reg [1:0] row_in, col_in;
  reg pol_in;
  wire busy, valid_out;
  wire [N_THETA_BITS-1:0] theta_out;

  wire [2*COORD_BITS-1:0] mem_addr;
  wire                    mem_we;
  wire [7:0]              mem_wdata;
  wire [7:0]              mem_rdata;

  bayes_filter #(.N_THETA_BITS(N_THETA_BITS), .COORD_BITS(COORD_BITS)) dut (
    .clk(clk), .rst(rst),
    .valid_in(valid_in), .row_in(row_in), .col_in(col_in), .pol_in(pol_in),
    .busy(busy), .valid_out(valid_out), .theta_out(theta_out),
    .mem_addr(mem_addr), .mem_we(mem_we), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
  );

  sync_sram_1rw #(.ADDR_BITS(2*COORD_BITS), .DATA_BITS(8)) u_wmem (
    .clk(clk), .addr(mem_addr), .we(mem_we), .wdata(mem_wdata), .rdata(mem_rdata)
  );

  always #5 clk = ~clk;

  integer fd, scan_ret;
  integer v_row, v_col, v_pol, v_theta;
  integer checked, mismatches;

  task automatic issue_and_check;
    begin
      @(posedge clk); #1;
      while (busy) begin @(posedge clk); #1; end
      row_in = v_row[1:0]; col_in = v_col[1:0]; pol_in = v_pol[0];
      valid_in = 1'b1;
      @(posedge clk); #1;
      valid_in = 1'b0;
      while (!valid_out) begin @(posedge clk); #1; end
      checked = checked + 1;
      if (theta_out !== v_theta[N_THETA_BITS-1:0]) begin
        mismatches = mismatches + 1;
        if (mismatches <= 10)
          $display("MISMATCH ev=%0d row=%0d col=%0d pol=%0d expected=%0d got=%0d",
                    checked, v_row, v_col, v_pol, v_theta, theta_out);
      end
    end
  endtask

  initial begin
    rst = 1; valid_in = 0; row_in = 0; col_in = 0; pol_in = 0;
    checked = 0; mismatches = 0;
    @(posedge clk); #1; rst = 0;
    // §134부터 world memory가 외부 SRAM(초기화는 sync_sram_1rw의 initial 블록)이라
    // bayes_filter 자체엔 ST_CLEAR가 없음 -- rst 해제 직후 바로 ST_IDLE.

    fd = $fopen("tb/bayes_filter_uzh_vectors.txt", "r");
    if (fd == 0) begin $display("CANNOT_OPEN_VECTORS"); $finish; end
    scan_ret = $fscanf(fd, "%d %d %d %d", v_row, v_col, v_pol, v_theta);
    while (scan_ret == 4) begin
      issue_and_check;
      scan_ret = $fscanf(fd, "%d %d %d %d", v_row, v_col, v_pol, v_theta);
    end
    $fclose(fd);

    $display("checked=%0d mismatches=%0d", checked, mismatches);
    if (checked > 0 && mismatches == 0)
      $display("BAYES_FILTER_UZH_TRACE_PASS");
    else
      $display("BAYES_FILTER_UZH_TRACE_FAIL");
    $finish;
  end
endmodule
