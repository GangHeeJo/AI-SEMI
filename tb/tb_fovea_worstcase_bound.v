// habituation(DS) 재설계 착수 전, 진짜 필요한지부터 확인 -- 완전 포화 상태에서
// 특정 소스(row+col 하나)가 최악의 경우 몇 사이클까지 기다리는지 정확히 측정.
// 이론값: row팀 레벨 gap<=WEIGHT+1, row0/row3(또는row1/row2) 교대<=x2,
// col 4-way 공정중재<=x4 => 주변 소스 최악 <= 8*(WEIGHT+1), 중심 소스는 훨씬 작음.
// DS/habituation은 원래 "무한정 밀리는 걸 막는" anti-starvation 장치인데, 이미
// 유한하고 작은 상한이 구조적으로 보장된다면 추가 회로가 불필요하다는 걸 확인하는 게 목적.
`timescale 1ns/1ps
module tb_fovea_worstcase_bound;
  parameter WEIGHT = 5;
  parameter CYCLES = 20000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid;
  wire [3:0] addr;

  aer_tx16_trad_rowcol_fovea #(.WEIGHT(WEIGHT)) tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));

  always #5 clk = ~clk;

  integer last_grant [0:15];
  integer max_gap [0:15];
  integer visits [0:15];
  integer cyc, i;

  function is_center_row(input integer idx_);
    is_center_row = (idx_[3:2] == 2'd1 || idx_[3:2] == 2'd2); // row1,row2
  endfunction

  initial begin
    for (i = 0; i < 16; i = i + 1) begin last_grant[i] = -1; max_gap[i] = 0; visits[i] = 0; end
    rst = 1; req = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // 완전 포화: 16개 전부 항상 요청 -- 최악의 경합 상태.
    req = 16'hFFFF;
    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid) begin
        if (last_grant[addr] >= 0) begin
          if ((cyc - last_grant[addr]) > max_gap[addr]) max_gap[addr] = cyc - last_grant[addr];
        end
        last_grant[addr] = cyc;
        visits[addr] = visits[addr] + 1;
      end
    end

    $display("WEIGHT=%0d, 이론 상한(주변)=%0d cycles", WEIGHT, 8*(WEIGHT+1));
    for (i = 0; i < 16; i = i + 1) begin
      $display("source=%0d (%s) visits=%0d max_gap=%0d", i, is_center_row(i) ? "center" : "periph", visits[i], max_gap[i]);
    end
    $finish;
  end
endmodule
