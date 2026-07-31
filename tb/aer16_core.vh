// aer_tx16 계열(기본판/fovea판 등) 공용 정확성 검증 코어. `TX 매크로로 송신기 모듈 지정.
module tb_aer16;
  reg clk = 0;
  reg rst;
  reg [15:0] req;

  wire       valid;
  wire       addr_type;
  wire [1:0] addr;

  wire       event_valid;
  wire [1:0] event_row;
  wire [1:0] event_col;

  `ifndef TX_PARAMS
  `define TX_PARAMS
  `endif
  `TX `TX_PARAMS tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  reg [15:0] seen;
  integer errors;
  integer i;

  task run_case(input [15:0] pattern, input integer cycles, input [8*20:1] label);
    integer c;
    integer errors_before;
    begin
      errors_before = errors;
      req = 16'd0;
      repeat (10) begin @(posedge clk); #1; end
      if (valid !== 1'b0)
        $display("WARN[%0s]: drain 후에도 valid=1 -- 파이프라인이 안 비워짐", label);

      req = pattern;
      seen = 16'd0;
      for (c = 0; c < cycles; c = c + 1) begin
        @(posedge clk); #1;
        if (event_valid) begin
          i = event_row * 4 + event_col;
          if (!pattern[i]) begin
            $display("FAIL[%0s]: req에 없는 이벤트(row=%0d,col=%0d, idx=%0d)가 복원됨", label, event_row, event_col, i);
            errors = errors + 1;
          end
          seen[i] = 1'b1;
        end
      end
      if ((seen & pattern) !== pattern) begin
        $display("FAIL[%0s]: pattern=%b 중 seen=%b -- 복원 안 된 이벤트 있음", label, pattern, seen);
        errors = errors + 1;
      end
      if (errors == errors_before)
        $display("PASS[%0s]: pattern=%b 전부 정확히 복원됨 (스퓨리어스 이벤트 없음)", label, pattern);
      else
        $display("FAIL[%0s]: 위에서 발견된 오류 %0d건 있음", label, errors - errors_before);
    end
  endtask

  initial begin
    $dumpfile("aer16.vcd");
    $dumpvars(0, tb_aer16);
    errors = 0;
    rst = 1; req = 16'd0; @(posedge clk); #1; rst = 0;

    run_case(16'b0000_0000_0100_0000, 60, "단일이벤트_row1col2");
    run_case(16'b0000_0000_1011_0000, 80, "같은행다중_row1_col013");
    run_case(16'b0010_0000_1000_0001, 150, "여러행동시_row0c0_row2c3_row3c1");
    run_case(16'hFFFF, 400, "전체16개동시요청");

    if (errors == 0) $display("=== 전체 PASS: 파이프라인 정확성 검증 완료 ===");
    else $display("=== 전체 FAIL: %0d건 실패 ===", errors);
    $finish;
  end
endmodule
