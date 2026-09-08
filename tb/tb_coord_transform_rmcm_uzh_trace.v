// coord_transform_rmcm 실트래픽 검증 -- 실제 UZH shapes_rotation 4x4 patch 이벤트
// 8,503개 + 실제 groundtruth pose에서 뽑은 theta_idx를 그대로 태워서, 소프트웨어 오라클이
// 계산한 기대값(row col theta_idx X Y pol, scripts/coord_transform_model.py 기반)과
// 한 건도 안 틀리는지 확인하고, RTL 시뮬레이션으로 직접 world memory를 채워 커버리지를 보고한다.
`timescale 1ns/1ps
module tb_coord_transform_uzh_trace;
  reg clk = 0;
  reg rst = 1;
  reg signed [3:0] xc2_in = 0;
  reg signed [3:0] yc2_in = 0;
  reg [7:0] theta_idx = 0;
  reg valid_in = 0;
  wire valid_out;
  wire [5:0] x_out, y_out;

  coord_transform_rmcm dut(
    .clk(clk), .rst(rst),
    .valid_in(valid_in), .xc2_in(xc2_in), .yc2_in(yc2_in), .theta_idx(theta_idx),
    .valid_out(valid_out), .x_out(x_out), .y_out(y_out)
  );

  always #5 clk = ~clk;

  reg world_touched [0:63][0:63];
  integer wi, wj;

  integer fh, row, col, theta_v, exp_x, exp_y, pol, code;
  integer total, mismatches, filled;

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
    for (wi = 0; wi < 64; wi = wi + 1)
      for (wj = 0; wj < 64; wj = wj + 1)
        world_touched[wi][wj] = 1'b0;

    @(negedge clk); rst = 0;

    fh = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.coord_transform_vectors.txt", "r");
    if (fh == 0) begin
      $display("FAIL: cannot open coord_transform_vectors.txt");
      $finish;
    end

    total = 0; mismatches = 0;
    while (!$feof(fh)) begin
      code = $fscanf(fh, "%d %d %d %d %d %d\n", row, col, theta_v, exp_x, exp_y, pol);
      if (code == 6) begin
        drive_one(row, col, theta_v);
        total = total + 1;
        if (!valid_out || x_out !== exp_x[5:0] || y_out !== exp_y[5:0]) begin
          mismatches = mismatches + 1;
          if (mismatches <= 10)
            $display("MISMATCH #%0d row=%0d col=%0d theta=%0d expected=(%0d,%0d) got=(%0d,%0d)",
                      total, row, col, theta_v, exp_x, exp_y, x_out, y_out);
        end else begin
          world_touched[y_out][x_out] = 1'b1;
        end
      end
    end
    $fclose(fh);

    filled = 0;
    for (wi = 0; wi < 64; wi = wi + 1)
      for (wj = 0; wj < 64; wj = wj + 1)
        if (world_touched[wi][wj]) filled = filled + 1;

    $display("total=%0d mismatches=%0d world_cells_filled=%0d/4096", total, mismatches, filled);
    if (total == 8503 && mismatches == 0)
      $display("COORD_TRANSFORM_RMCM_UZH_TRACE_PASS");
    else
      $display("COORD_TRANSFORM_RMCM_UZH_TRACE_FAIL");
    $finish;
  end
endmodule
