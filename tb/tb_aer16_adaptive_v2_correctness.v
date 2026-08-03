// aer_tx16_adaptive_v2 기능 정확성 검증 — 큐 기반 트래픽으로 req/new_event를 제대로 모델링.
// (new_event는 "그 사이클에 실제로 새 이벤트가 도착했는가" 펄스, req는 "아직 밀려있는가" 레벨)
module tb_aer16_adaptive_v2_correctness;
  parameter QDEPTH = 64;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [15:0] new_event;

  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  `ifndef WEIGHT_VAL
  `define WEIGHT_VAL 3
  `endif
  `ifndef DECAY_SHIFT_VAL
  `define DECAY_SHIFT_VAL 6
  `endif
  aer_tx16_adaptive_v2 #(.WEIGHT(`WEIGHT_VAL), .DECAY_SHIFT(`DECAY_SHIFT_VAL)) tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  reg [15:0] seen;
  integer errors, errors_before;
  integer i, idx;

  task run_case(input [15:0] pattern, input integer cycles, input [8*20:1] label);
    integer c;
    begin
      errors_before = errors;
      // 완전히 비우기
      score.init;
      req = 16'd0; new_event = 16'd0;
      repeat (10) begin @(posedge clk); #1; end

      seen = 16'd0;
      for (c = 0; c < cycles; c = c + 1) begin
        // pattern의 각 비트에 해당하는 셀에, 아직 큐가 비어있으면(=서비스된 뒤) 새 이벤트를 다시 채워넣는다
        // (지속적으로 요청이 발생하는 상황을 큐 기반으로 재현)
        new_event = 16'd0;
        for (i = 0; i < 16; i = i + 1) begin
          if (pattern[i] && score.qcount[i] == 0) begin
            score.record_arrival(i, c);
            new_event[i] = 1'b1;
          end
        end
        for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

        @(posedge clk); #1;

        if (event_valid) begin
          idx = event_row*4 + event_col;
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
        $display("FAIL[%0s]: 복원 안 된 이벤트 있음 (seen=%b, pattern=%b)", label, seen, pattern);
        errors = errors + 1;
      end
      if (errors == errors_before) $display("PASS[%0s]", label);
      else $display("FAIL[%0s]: %0d건", label, errors-errors_before);
    end
  endtask

  initial begin
    errors = 0;
    rst = 1; req = 16'd0; new_event = 16'd0; @(posedge clk); #1; rst = 0;

    run_case(16'b0000_0000_0100_0000, 60, "단일이벤트");
    run_case(16'b0000_0000_1011_0000, 80, "같은행다중");
    run_case(16'b0010_0000_1000_0001, 3000, "여러행동시");
    run_case(16'hFFFF, 20000, "전체16개");

    if (errors == 0) $display("=== 전체 PASS ===");
    else $display("=== 전체 FAIL: %0d건 ===", errors);
    $finish;
  end
endmodule
