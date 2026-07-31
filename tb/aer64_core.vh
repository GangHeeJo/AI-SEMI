// aer_tx64 계열 공용 정확성 검증 코어 (8x8=64셀). `TX 매크로로 송신기 모듈 지정.
module tb_aer64;
  reg clk = 0;
  reg rst;
  reg [63:0] req;

  wire       valid;
  wire       addr_type;
  wire [2:0] addr;

  wire       event_valid;
  wire [2:0] event_row;
  wire [2:0] event_col;

  `ifndef TX_PARAMS
  `define TX_PARAMS
  `endif
  `TX `TX_PARAMS tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  reg [63:0] seen;
  integer errors;
  integer i;

  task run_case(input [63:0] pattern, input integer cycles, input [8*20:1] label);
    integer c;
    integer errors_before;
    begin
      errors_before = errors;
      req = 64'd0;
      repeat (16) begin @(posedge clk); #1; end
      if (valid !== 1'b0)
        $display("WARN[%0s]: drain 후에도 valid=1", label);

      req = pattern;
      seen = 64'd0;
      for (c = 0; c < cycles; c = c + 1) begin
        @(posedge clk); #1;
        if (event_valid) begin
          i = event_row * 8 + event_col;
          if (!pattern[i]) begin
            $display("FAIL[%0s]: req에 없는 이벤트(row=%0d,col=%0d, idx=%0d)가 복원됨", label, event_row, event_col, i);
            errors = errors + 1;
          end
          seen[i] = 1'b1;
        end
      end
      if ((seen & pattern) !== pattern) begin
        $display("FAIL[%0s]: 복원 안 된 이벤트 있음", label);
        errors = errors + 1;
      end
      if (errors == errors_before)
        $display("PASS[%0s]: 전부 정확히 복원됨", label);
      else
        $display("FAIL[%0s]: 오류 %0d건", label, errors - errors_before);
    end
  endtask

  initial begin
    errors = 0;
    rst = 1; req = 64'd0; @(posedge clk); #1; rst = 0;

    run_case(64'h0000_0010_0000_0000, 100, "단일이벤트");
    run_case(64'h0000_0000_0000_00B0, 150, "행0다중열");
    run_case({8'h81, 48'h0, 8'h81}, 300, "여러행동시"); // row7 col0,7 + row0 col0,7
    run_case(64'hFFFF_FFFF_FFFF_FFFF, 1200, "전체64개동시요청");

    if (errors == 0) $display("=== 전체 PASS: 64셀 파이프라인 정확성 검증 완료 ===");
    else $display("=== 전체 FAIL: %0d건 실패 ===", errors);
    $finish;
  end
endmodule
