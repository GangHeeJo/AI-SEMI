// coord_transform_rmcm 전수 검사(4x4 x 256 theta = 4096가지 전부).
// scripts/coord_transform_model.py의 export_exhaustive_vectors()가 만든
// tb/coord_transform_exhaustive_vectors.txt("row col theta_idx X Y" 한 줄씩)를
// 그대로 읽어 DUT를 구동하고, 소프트웨어 오라클이 낸 기대값과 비트 단위로 비교한다.
`timescale 1ns/1ps
module tb_coord_transform_rmcm_correctness;
  reg clk = 0;
  reg rst = 1;
  reg valid_in = 0;
  reg signed [3:0] xc2_in = 0;
  reg signed [3:0] yc2_in = 0;
  reg [7:0] theta_idx = 0;
  wire valid_out;
  wire [5:0] x_out, y_out;

  coord_transform_rmcm dut(
    .clk(clk), .rst(rst),
    .valid_in(valid_in), .xc2_in(xc2_in), .yc2_in(yc2_in), .theta_idx(theta_idx),
    .valid_out(valid_out), .x_out(x_out), .y_out(y_out)
  );

  always #5 clk = ~clk;

  integer fh, row, col, theta_v, exp_x, exp_y, code;
  integer total, mismatches;

  task automatic drive_one(input integer row_i, input integer col_i, input integer theta_i);
    begin
      xc2_in = 2*col_i - 3;
      yc2_in = 2*row_i - 3;
      theta_idx = theta_i;
      valid_in = 1;
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    @(negedge clk); rst = 0;

    fh = $fopen("tb/coord_transform_exhaustive_vectors.txt", "r");
    if (fh == 0) begin
      $display("FAIL: cannot open tb/coord_transform_exhaustive_vectors.txt");
      $finish;
    end

    total = 0; mismatches = 0;
    while (!$feof(fh)) begin
      code = $fscanf(fh, "%d %d %d %d %d\n", row, col, theta_v, exp_x, exp_y);
      if (code != 5) begin
        // 파일 끝의 빈 줄 등 -- 그냥 건너뜀
      end else begin
        drive_one(row, col, theta_v);
        total = total + 1;
        if (!valid_out || x_out !== exp_x[5:0] || y_out !== exp_y[5:0]) begin
          mismatches = mismatches + 1;
          if (mismatches <= 10)
            $display("MISMATCH row=%0d col=%0d theta=%0d expected=(%0d,%0d) got=(%0d,%0d) valid=%0d",
                      row, col, theta_v, exp_x, exp_y, x_out, y_out, valid_out);
        end
      end
    end
    $fclose(fh);

    $display("total=%0d mismatches=%0d", total, mismatches);
    if (total == 4096 && mismatches == 0)
      $display("COORD_TRANSFORM_RMCM_EXHAUSTIVE_PASS");
    else
      $display("COORD_TRANSFORM_RMCM_EXHAUSTIVE_FAIL");
    $finish;
  end
endmodule
