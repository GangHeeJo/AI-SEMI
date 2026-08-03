// aer_tx64_adaptive_v2 기능 정확성 검증 (큐 기반, req/new_event 제대로 구분해서 모델링).
module tb_aer64_adaptive_v2_correctness;
  parameter QDEPTH = 64;
  reg clk = 0;
  reg rst;
  reg [63:0] req;
  reg [63:0] new_event;

  wire       valid, addr_type;
  wire [2:0] addr;
  wire       event_valid;
  wire [2:0] event_row, event_col;

  aer_tx64_adaptive_v2 tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  event_scoreboard #(.N(64), .QDEPTH(QDEPTH)) score();
  reg [63:0] seen;
  integer errors, errors_before;
  integer i, idx;

  task run_case(input [63:0] pattern, input integer cycles, input [8*20:1] label);
    integer c;
    begin
      errors_before = errors;
      score.init;
      req = 64'd0; new_event = 64'd0;
      repeat (20) begin @(posedge clk); #1; end

      seen = 64'd0;
      for (c = 0; c < cycles; c = c + 1) begin
        new_event = 64'd0;
        for (i = 0; i < 64; i = i + 1) begin
          if (pattern[i] && score.qcount[i] == 0) begin
            score.record_arrival(i, c);
            new_event[i] = 1'b1;
          end
        end
        for (i = 0; i < 64; i = i + 1) req[i] = (score.qcount[i] > 0);

        @(posedge clk); #1;

        if (event_valid) begin
          idx = event_row*8 + event_col;
          if (!pattern[idx]) begin
            $display("FAIL[%0s]: req에 없는 이벤트(row=%0d,col=%0d)가 복원됨", label, event_row, event_col);
            errors = errors + 1;
          end
          if (score.record_departure(idx, c) < 0) begin
            $display("FAIL[%0s]: phantom 이벤트(row=%0d,col=%0d, 밀린 게 없었음)", label, event_row, event_col);
            errors = errors + 1;
          end
          seen[idx] = 1'b1;
        end
      end
      if ((seen & pattern) !== pattern) begin
        $display("FAIL[%0s]: 복원 안 된 이벤트 있음", label);
        errors = errors + 1;
      end
      if (errors == errors_before) $display("PASS[%0s]", label);
      else $display("FAIL[%0s]: %0d건", label, errors-errors_before);
    end
  endtask

  initial begin
    errors = 0;
    rst = 1; req = 64'd0; new_event = 64'd0; @(posedge clk); #1; rst = 0;

    run_case(64'h0000_0010_0000_0000, 200, "단일이벤트");
    run_case(64'h0000_0000_0000_00B0, 300, "행0다중열");
    run_case({8'h81, 48'h0, 8'h81}, 1000, "여러행동시");
    run_case(64'hFFFF_FFFF_FFFF_FFFF, 4000, "전체64개동시요청");

    if (errors == 0) $display("=== 전체 PASS: 64셀 v2 정확성 검증 완료 ===");
    else $display("=== 전체 FAIL: %0d건 실패 ===", errors);
    $finish;
  end
endmodule
