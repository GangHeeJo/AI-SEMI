// cluster2_refractory 정확성/보존 검증. suppressed는 arrival 직후(엣지 전, combinational
// 안정 시점)에 샘플링해야 함(§44 tb_buf_correctness.v에서 겪은 것과 같은 타이밍 함정 --
// 이번엔 처음부터 올바른 위치에 샘플링).
// 보존식: generated = delivered + suppressed + retrigger_drop + 마지막에 남은 pending 수.
`timescale 1ns/1ps
module tb_refractory_correctness;
  parameter R = 2;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;
  parameter DRAIN_CYCLES = 200;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] suppressed_w, retrigger_drop_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_refractory #(.R(R)) dut(
    .clk(clk), .rst(rst), .arrival(arrival),
    .suppressed(suppressed_w), .retrigger_drop(retrigger_drop_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 3;
  integer cyc, i, c, draw, idx, phantom_count, error_count;
  integer generated, delivered, suppressed_cnt, retrig_cnt;
  reg shadow_pending [0:15];

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (!shadow_pending[idx]) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM cyc=%0d idx=%0d", cyc, idx);
            end else begin
              delivered = delivered + 1;
            end
            shadow_pending[idx] = 1'b0;
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; suppressed_cnt = 0; retrig_cnt = 0;
    phantom_count = 0; error_count = 0;
    for (i = 0; i < 16; i = i + 1) shadow_pending[i] = 1'b0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          arrival[i] = 1'b1;
        end
      end
      #1; // arrival 안정, 엣지 전 -- suppressed/retrigger_drop은 combinational이라 지금 샘플.
      for (i = 0; i < 16; i = i + 1) begin
        if (suppressed_w[i]) suppressed_cnt = suppressed_cnt + 1;
        if (retrigger_drop_w[i]) retrig_cnt = retrig_cnt + 1;
        // shadow: suppressed/retrigger가 아니고 아직 pending도 아니면 이번에 accept.
        if (arrival[i] && !suppressed_w[i] && !retrigger_drop_w[i] && !shadow_pending[i])
          shadow_pending[i] = 1'b1;
      end

      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
    end

    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + DRAIN_CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
    end

    for (i = 0; i < 16; i = i + 1) begin
      if (shadow_pending[i]) begin
        error_count = error_count + 1;
        $display("DRAIN_INCOMPLETE source=%0d", i);
      end
    end

    if ((delivered + suppressed_cnt + retrig_cnt) != generated) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH delivered=%0d suppressed=%0d retrig=%0d sum=%0d generated=%0d",
        delivered, suppressed_cnt, retrig_cnt, delivered+suppressed_cnt+retrig_cnt, generated);
    end

    $display("R=%0d generated=%0d delivered=%0d suppressed=%0d retrigger_drop=%0d phantom=%0d",
      R, generated, delivered, suppressed_cnt, retrig_cnt, phantom_count);

    if (error_count == 0) $display("REFRACTORY_CORRECTNESS_PASS");
    else $display("REFRACTORY_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
