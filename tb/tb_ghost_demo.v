// aer_tx16_ghost_demo가 실제로 유령 이벤트를 만드는지 검증: 매 grant마다 그 (row,col)
// 주소에 해당하는 req 비트가 실제로 서있었는지(=진짜 요청이 있었는지) 직접 확인한다.
// true_traditional(행 종속 열 중재)과 나란히 돌려서 대조.
`timescale 1ns/1ps
module tb_ghost_demo;
  parameter CYCLES = 3000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  always #5 clk = ~clk;

  wire ghost_valid;
  wire [3:0] ghost_addr;
  aer_tx16_ghost_demo ghost_dut(.clk(clk), .rst(rst), .req(req), .valid(ghost_valid), .addr(ghost_addr));

  wire trad_valid;
  wire [3:0] trad_addr;
  aer_tx16_trad_rowcol trad_dut(.clk(clk), .rst(rst), .req(req), .valid(trad_valid), .addr(trad_addr));

  // 한 사이클 지연된(등록 시점의) req를 남겨서, "그랜트가 이 req를 근거로 한 게 맞는지" 확인.
  reg [15:0] req_at_grant_time;

  integer cyc, i, ghost_count, trad_ghost_count;

  initial begin
    rst = 1; req = 16'd0; ghost_count = 0; trad_ghost_count = 0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1)
        req[i] = ((($random % 100) + 100) % 100 < ARRIVAL_PCT) ? 1'b1 : req[i]; // 레벨 유지(서비스 안 됐으면 계속 요청)

      req_at_grant_time = req; // 이번 grant 판단의 근거가 된 req 스냅샷

      @(posedge clk); #1;

      if (ghost_valid) begin
        if (req_at_grant_time[ghost_addr] !== 1'b1) begin
          ghost_count = ghost_count + 1;
          $display("GHOST EVENT 발생: cycle=%0d addr=%0d(row=%0d,col=%0d) — 이 주소는 req에 없었음!",
                    cyc, ghost_addr, ghost_addr[3:2], ghost_addr[1:0]);
        end else begin
          req[ghost_addr] = 1'b0; // 정상 처리된 것만 서비스 완료로 내림(간단화)
        end
      end

      if (trad_valid) begin
        if (req_at_grant_time[trad_addr] !== 1'b1)
          trad_ghost_count = trad_ghost_count + 1;
        // true_traditional은 req를 별도로 안 내림(단순 확인용이라 phantom 검증은 생략, 유령 여부만 봄)
      end
    end

    $display("=== ghost_demo(행-열 독립 중재): %0d 사이클 중 유령 이벤트 %0d건 발생 ===", CYCLES, ghost_count);
    $display("=== true_traditional(행 종속 열 중재): %0d 사이클 중 유령 이벤트 %0d건 발생 ===", CYCLES, trad_ghost_count);
    $finish;
  end
endmodule
