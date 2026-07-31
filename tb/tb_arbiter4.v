module tb_arbiter4;
  reg clk = 0;
  reg rst;
  reg [3:0] req;
  wire [3:0] gnt;
  integer errors = 0;
  integer i;
  integer grant_count [0:3];

  arbiter4 dut(.clk(clk), .rst(rst), .req(req), .gnt(gnt));

  always #5 clk = ~clk;

  task check_onehot_or_zero;
    begin
      // gnt must never grant more than one requester at once
      if ((gnt & (gnt - 1)) !== 0) begin
        $display("FAIL: gnt=%b is not one-hot/zero", gnt);
        errors = errors + 1;
      end
      // gnt must only pick someone who actually requested
      if ((gnt & ~req) !== 0) begin
        $display("FAIL: gnt=%b granted a non-requester (req=%b)", gnt, req);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    $dumpfile("arbiter4.vcd");
    $dumpvars(0, tb_arbiter4);

    for (i = 0; i < 4; i = i + 1) grant_count[i] = 0;

    rst = 1; req = 4'b0000; @(posedge clk); #1;
    rst = 0;

    // Case 1: only requester 2 asks -> must be granted to it
    req = 4'b0100; @(posedge clk); #1;
    check_onehot_or_zero;
    if (gnt !== 4'b0100) begin
      $display("FAIL: single request req=%b expected gnt=0100 got %b", req, gnt);
      errors = errors + 1;
    end

    // Case 2: all four request continuously -> must rotate through all 4
    // without ever granting the same one twice before the others get a turn
    req = 4'b1111;
    for (i = 0; i < 8; i = i + 1) begin
      @(posedge clk); #1;
      check_onehot_or_zero;
      if (gnt[0]) grant_count[0] = grant_count[0] + 1;
      if (gnt[1]) grant_count[1] = grant_count[1] + 1;
      if (gnt[2]) grant_count[2] = grant_count[2] + 1;
      if (gnt[3]) grant_count[3] = grant_count[3] + 1;
    end
    // over 8 cycles of sustained contention, each requester should get exactly 2 turns
    for (i = 0; i < 4; i = i + 1) begin
      if (grant_count[i] !== 2) begin
        $display("FAIL: fairness broken, requester %0d got %0d grants (expected 2)", i, grant_count[i]);
        errors = errors + 1;
      end
    end

    // Case 3: no one requests -> no grant
    req = 4'b0000; @(posedge clk); #1;
    check_onehot_or_zero;
    if (gnt !== 4'b0000) begin
      $display("FAIL: req=0000 but gnt=%b", gnt);
      errors = errors + 1;
    end

    if (errors == 0) $display("PASS: all arbiter4 checks passed");
    else $display("FAIL: %0d check(s) failed", errors);
    $finish;
  end
endmodule
