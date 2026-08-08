// lane4는 중재가 아예 없어서(모든 행이 매 사이클 무조건 통과) req[15:0]이 1사이클 뒤에
// {valid0,col_mask0,...,valid3,col_mask3}로 그대로 나타나야 함 -- 이 등식이 매 사이클
// 항상 성립하는지 무작위 자극으로 확인.
`timescale 1ns/1ps
module tb_lane4_correctness;
  parameter CYCLES = 5000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0, valid1, valid2, valid3;
  wire [3:0] col_mask0, col_mask1, col_mask2, col_mask3;

  aer_tx16_lane4 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .col_mask0(col_mask0),
    .valid1(valid1), .col_mask1(col_mask1),
    .valid2(valid2), .col_mask2(col_mask2),
    .valid3(valid3), .col_mask3(col_mask3));

  always #5 clk = ~clk;

  integer rng_seed = 7;
  integer cyc, draw, i, errors;

  initial begin
    rst = 1; req = 16'd0; errors = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      req = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 30) req[i] = 1'b1;
      end
      @(posedge clk); #1;
      // 방금 설정한 req가 이 엣지에 그대로 등록되어 나옴(중재/지연 없음, 1사이클 등록만).
      if ({valid0, col_mask0} !== {|req[3:0], req[3:0]}) begin
        errors = errors + 1;
        $display("MISMATCH row0 cyc=%0d expect_valid=%0d expect_mask=%b got_valid=%0d got_mask=%b",
          cyc, |req[3:0], req[3:0], valid0, col_mask0);
      end
      if ({valid1, col_mask1} !== {|req[7:4], req[7:4]}) begin
        errors = errors + 1;
        $display("MISMATCH row1 cyc=%0d", cyc);
      end
      if ({valid2, col_mask2} !== {|req[11:8], req[11:8]}) begin
        errors = errors + 1;
        $display("MISMATCH row2 cyc=%0d", cyc);
      end
      if ({valid3, col_mask3} !== {|req[15:12], req[15:12]}) begin
        errors = errors + 1;
        $display("MISMATCH row3 cyc=%0d", cyc);
      end
    end

    if (errors == 0) $display("LANE4_CORRECTNESS_PASS cycles=%0d", CYCLES);
    else $display("LANE4_CORRECTNESS_FAIL errors=%0d", errors);
    $finish;
  end
endmodule
