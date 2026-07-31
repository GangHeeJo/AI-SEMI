module tb_arbiter8;
  reg clk = 0;
  reg rst;
  reg [7:0] req;
  wire [7:0] gnt;
  integer errors = 0;
  integer i;
  integer grant_count [0:7];

  arbiter8 dut(.clk(clk), .rst(rst), .req(req), .gnt(gnt));

  always #5 clk = ~clk;

  task check_onehot_or_zero;
    begin
      if ((gnt & (gnt - 1)) !== 0) begin
        $display("FAIL: gnt=%b is not one-hot/zero", gnt);
        errors = errors + 1;
      end
      if ((gnt & ~req) !== 0) begin
        $display("FAIL: gnt=%b granted a non-requester (req=%b)", gnt, req);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    for (i = 0; i < 8; i = i + 1) grant_count[i] = 0;
    rst = 1; req = 8'b0; @(posedge clk); #1;
    rst = 0;

    req = 8'b00000100; @(posedge clk); #1;
    check_onehot_or_zero;
    if (gnt !== 8'b00000100) begin
      $display("FAIL: single request req=%b expected gnt matching, got %b", req, gnt);
      errors = errors + 1;
    end

    req = 8'hFF;
    for (i = 0; i < 16; i = i + 1) begin
      @(posedge clk); #1;
      check_onehot_or_zero;
      if (gnt[0]) grant_count[0]=grant_count[0]+1; if (gnt[1]) grant_count[1]=grant_count[1]+1;
      if (gnt[2]) grant_count[2]=grant_count[2]+1; if (gnt[3]) grant_count[3]=grant_count[3]+1;
      if (gnt[4]) grant_count[4]=grant_count[4]+1; if (gnt[5]) grant_count[5]=grant_count[5]+1;
      if (gnt[6]) grant_count[6]=grant_count[6]+1; if (gnt[7]) grant_count[7]=grant_count[7]+1;
    end
    for (i = 0; i < 8; i = i + 1) begin
      if (grant_count[i] !== 2) begin
        $display("FAIL: fairness broken, requester %0d got %0d grants (expected 2)", i, grant_count[i]);
        errors = errors + 1;
      end
    end

    req = 8'b0; @(posedge clk); #1;
    check_onehot_or_zero;
    if (gnt !== 8'b0) begin
      $display("FAIL: req=0 but gnt=%b", gnt);
      errors = errors + 1;
    end

    if (errors == 0) $display("PASS: all arbiter8 checks passed");
    else $display("FAIL: %0d check(s) failed", errors);
    $finish;
  end
endmodule
