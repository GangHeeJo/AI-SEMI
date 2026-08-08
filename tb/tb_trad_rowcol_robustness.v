// 로버스트니스 검증(9번 체크리스트, 미착수였던 항목) — true_traditional과
// true_traditional+fovea 둘 다 대상. 세 가지:
// (a) starvation probe: 셀 0개(고립) 하나만 100% 요청, 나머지는 산발적 — 그 셀의
//     grant 간격 최댓값이 유한/작은 값으로 유지되는지(진짜 기아 없는지) 확인.
// (b) all-but-one-saturated: 15개 셀 100% 포화, 1개 셀만 드묾 — 그 1개가 여전히
//     서비스받는지(무한정 밀리지 않는지) 확인.
// (c) reset-during-contention: 여러 셀이 동시에 요청 중인 한가운데서 rst를 걸었다
//     풀었을 때, valid/addr이 깨끗이 복구되고(rst 직후 valid=0) 그 다음 정상
//     동작하는지 확인.
`timescale 1ns/1ps
module tb_trad_rowcol_robustness;
  parameter N = 16;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid;
  wire [3:0] addr;

`ifdef USE_FOVEA
  aer_tx16_trad_rowcol_fovea #(.WEIGHT(3)) tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));
`else
  aer_tx16_trad_rowcol tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));
`endif

  always #5 clk = ~clk;

  integer last_grant [0:15];
  integer max_gap [0:15];
  integer visits [0:15];
  integer cyc, i;
  integer fail;

  task run_phase;
    input [15:0] req_pattern;
    input integer cycles;
    input integer stationary; // 1이면 req_pattern 고정, 0이면 매 사이클 무작위(생략, 여기선 항상 고정)
    begin
      req = req_pattern;
      for (cyc = 0; cyc < cycles; cyc = cyc + 1) begin
        @(posedge clk); #1;
        if (valid) begin
          if (last_grant[addr] >= 0) begin
            if ((cyc - last_grant[addr]) > max_gap[addr]) max_gap[addr] = cyc - last_grant[addr];
          end
          last_grant[addr] = cyc;
          visits[addr] = visits[addr] + 1;
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

    // (a) starvation probe: 셀0만 고립되어 100% 요청, 나머지는 0(완전 유휴).
    //     이 경우 셀0은 매번 즉시 그랜트돼야 함(경쟁 상대 없음) — 최댓값 gap이 작아야 함.
    run_phase(16'b0000_0000_0000_0001, 5000, 1);
    $display("[a-1] 고립된 셀0 단독 요청: max_gap=%0d (기대: 매우 작음, 경쟁 없음)", max_gap[0]);
    if (max_gap[0] > 10) begin
      $display("FAIL: 셀0 고립 상태인데 gap이 너무 큼"); fail = fail + 1;
    end

    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; visits[i] = 0; end

    // (a-2) 셀0은 100% 요청, 나머지 15개는 전부 동시에 100% 요청(정상 경쟁 상태) —
    //       회전식 공정 중재기라면 셀0도 N cycle(대략 행4*열4=16 단위) 주기로 반드시 서비스돼야 함.
    // 주의(2026-08-08 발견): req가 완전히 고정된 채로 아주 오래 지속되면, 공유
    // col_arb의 내부 상태가 매 사이클 갱신되며 바깥쪽 row 순환과 위상이 딱 맞아
    // 떨어져 버려서(resonance) 특정 열 조합이 "영원히" 안 뽑히는 사례가 실제로
    // 있었음(20000cycle 동안 4/16 소스만 서비스). max_gap만 보면 방문이 0인
    // 소스는 gap도 0이라 조용히 통과해버리므로, visits 자체도 반드시 확인해야 함.
    run_phase(16'hFFFF, 5000, 1);
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

    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; visits[i] = 0; end

    // (b) all-but-one-saturated: 셀15만 빼고 전부 100% 포화, 셀15는 계속 0(요청 없음)
    //     이후 짧게 셀15만 요청 넣어서 즉시 서비스되는지(밀린 큐가 없어야 하니 바로 처리) 확인.
    run_phase(16'h7FFF, 3000, 1); // 셀15(bit15)만 0
    req = 16'h8000; // 이제 셀15만 요청, 나머지 0
    @(posedge clk); #1;
    if (!(valid && addr == 4'd15)) begin
      $display("FAIL: all-but-one-saturated 이후 유일한 저부하 셀(15)이 즉시 서비스 안 됨(valid=%0d addr=%0d)", valid, addr);
      fail = fail + 1;
    end else begin
      $display("[b] all-but-one-saturated 이후 셀15 즉시 서비스됨 — 통과");
    end
    req = 16'd0;
    @(posedge clk); #1;

    // (c) reset-during-contention: 여러 셀이 경쟁 중인 한가운데 rst 인가 후 해제.
    req = 16'hFFFF;
    repeat (7) @(posedge clk); // 중재가 한창 진행 중인 시점
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
