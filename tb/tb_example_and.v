module tb_example_and;
  reg a, b;
  wire y;

  example_and dut(.a(a), .b(b), .y(y));

  initial begin
    $dumpfile("example_and.vcd");
    $dumpvars(0, tb_example_and);
    a = 0; b = 0; #1;
    if (y !== 0) $display("FAIL a=0 b=0");
    a = 1; b = 1; #1;
    if (y !== 1) $display("FAIL a=1 b=1");
    else $display("PASS");
    $finish;
  end
endmodule
