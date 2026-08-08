// tb_trad_rowcol_robustness.v를 fovea_cluster(row+col_mask 인터페이스)용으로 이식.
// 같은 3가지 체크: (a) 고립 셀 기아 없음, (a-2) 전원포화 상태 최대 gap, (b) 나머지
// 포화 중 저부하 셀 즉시 서비스, (c) 경합 중 reset 복구.
`timescale 1ns/1ps
module tb_cluster_robustness;
  parameter N = 16;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid;
  wire [1:0] row;
  wire [3:0] col_mask;

  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(3)) tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .row(row), .col_mask(col_mask));

  always #5 clk = ~clk;

  integer last_grant [0:15];
  integer max_gap [0:15];
  integer visits [0:15];
  integer cyc, i, c, idx;
  integer fail;

  task run_phase;
    input [15:0] req_pattern;
    input integer cycles;
    begin
      req = req_pattern;
      for (cyc = 0; cyc < cycles; cyc = cyc + 1) begin
        @(posedge clk); #1;
        if (valid) begin
          for (c = 0; c < 4; c = c + 1) begin
            if (col_mask[c]) begin
              idx = row*4 + c;
              if (last_grant[idx] >= 0) begin
                if ((cyc - last_grant[idx]) > max_gap[idx]) max_gap[idx] = cyc - last_grant[idx];
              end
              last_grant[idx] = cyc;
              visits[idx] = visits[idx] + 1;
            end
          end
        end
      end
    end
  endtask

  initial begin
    fail = 0;
    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; visits[i] = 0; end
    rst = 1; req = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // (a) 고립된 셀0 단독 요청 -- 경쟁 없으니 매번 즉시 서비스돼야 함.
    run_phase(16'b0000_0000_0000_0001, 5000);
    $display("[a-1] 고립된 셀0 단독 요청: max_gap=%0d (기대: 매우 작음, 경쟁 없음)", max_gap[0]);
    if (max_gap[0] > 10) begin
      $display("FAIL: 셀0 고립 상태인데 gap이 너무 큼"); fail = fail + 1;
    end

    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; visits[i] = 0; end

    // (a-2) 전원 포화 -- cluster는 매 grant마다 최대 4개를 한꺼번에 빼내므로 gap이
    //       기존(단일배출) 방식보다 오히려 작거나 같아야 정상. 기존과 같은 상한(40)으로 확인.
    // true_traditional/fovea에서 발견된 "공유 col_arb 위상고정 영구기아" 버그(2026-08-08)가
    // cluster에는 없어야 함(col_arb 자체가 없으므로) -- visits==0인 소스가 있으면 안 됨.
    run_phase(16'hFFFF, 5000);
    for (i = 0; i < 16; i = i + 1)
      $display("[a-2] 전원 포화 상태, 셀%0d visits=%0d max_gap=%0d", i, visits[i], max_gap[i]);
    for (i = 0; i < 16; i = i + 1) begin
      if (visits[i] == 0) begin
        $display("FAIL: 셀%0d가 전원 포화 상태에서 5000cycle 내내 단 한 번도 서비스 안 됨(영구 기아)", i);
        fail = fail + 1;
      end else if (max_gap[i] > 40) begin
        $display("FAIL: 셀%0d가 전원 포화 상태에서 기아(gap=%0d, 기대 상한 근처 40)", i, max_gap[i]);
        fail = fail + 1;
      end
    end

    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; end

    // (b) all-but-one-saturated: 셀15만 빼고 포화, 이후 셀15만 요청하면 즉시 서비스돼야 함.
    run_phase(16'h7FFF, 3000);
    req = 16'h8000;
    @(posedge clk); #1;
    if (!(valid && row == 2'd3 && col_mask[3])) begin
      $display("FAIL: all-but-one-saturated 이후 유일한 저부하 셀(15)이 즉시 서비스 안 됨(valid=%0d row=%0d col_mask=%0b)", valid, row, col_mask);
      fail = fail + 1;
    end else begin
      $display("[b] all-but-one-saturated 이후 셀15 즉시 서비스됨 — 통과");
    end
    req = 16'd0;
    @(posedge clk); #1;

    // (c) reset-during-contention.
    req = 16'hFFFF;
    repeat (7) @(posedge clk);
    rst = 1;
    @(posedge clk); #1;
    if (valid !== 1'b0) begin
      $display("FAIL: rst 인가 직후에도 valid가 0이 아님(valid=%0d)", valid);
      fail = fail + 1;
    end else begin
      $display("[c-1] rst 인가 직후 valid=0 확인 — 통과");
    end
    rst = 0;
    req = 16'hFFFF;
    @(posedge clk); #1;
    if (!valid) begin
      $display("FAIL: rst 해제 후에도 포화 요청 상태에서 재개가 안 됨");
      fail = fail + 1;
    end else begin
      $display("[c-2] rst 해제 후 정상 재개(valid=1) — 통과");
    end

    if (fail == 0) $display("=== 로버스트니스 검증 전부 통과 ===");
    else $display("=== 로버스트니스 검증 실패 %0d건 ===", fail);
    $finish;
  end
endmodule
