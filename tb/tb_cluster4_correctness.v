// cluster4(4레인, 행마다 전용레인) 정확성 검증 -- tb_cluster2_correctness.v와 동일
// 방법론, 레인 4개로 확장. 무손실이 정의상 자명한 구조지만, "실제로도 그런지"를
// generated==delivered로 직접 확인.
`timescale 1ns/1ps
module tb_cluster4_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 200000;
  parameter ARRIVAL_PCT = 15;
  parameter DRAIN_CYCLES = 5000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [3:0] col_mask0;
  wire valid1; wire [3:0] col_mask1;
  wire valid2; wire [3:0] col_mask2;
  wire valid3; wire [3:0] col_mask3;

  aer_tx16_trad_rowcol_fovea_cluster4 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .col_mask0(col_mask0),
    .valid1(valid1), .col_mask1(col_mask1),
    .valid2(valid2), .col_mask2(col_mask2),
    .valid3(valid3), .col_mask3(col_mask3));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, lat;
  integer generated, delivered, phantom_count, error_count;
  integer idx;

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (score.qcount[idx] <= 0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM at cyc=%0d row=%0d col=%0d idx=%0d", cyc, row_in, c, idx);
            end else begin
              lat = score.record_departure(idx, cyc);
              delivered = delivered + 1;
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; req = 16'd0;
    generated = 0; delivered = 0; phantom_count = 0; error_count = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1)
        req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      drain_lane(valid0, 0, col_mask0);
      drain_lane(valid1, 1, col_mask1);
      drain_lane(valid2, 2, col_mask2);
      drain_lane(valid3, 3, col_mask3);
    end

    req = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + DRAIN_CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1)
        req[i] = (score.qcount[i] > 0);
      @(posedge clk); #1;
      drain_lane(valid0, 0, col_mask0);
      drain_lane(valid1, 1, col_mask1);
      drain_lane(valid2, 2, col_mask2);
      drain_lane(valid3, 3, col_mask3);
    end

    for (i = 0; i < N; i = i + 1) begin
      if (score.qcount[i] != 0) begin
        error_count = error_count + 1;
        $display("DRAIN_INCOMPLETE source=%0d qcount=%0d", i, score.qcount[i]);
      end
    end
    if (generated != delivered) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH generated=%0d delivered=%0d overflow=%0d", generated, delivered, score.overflow_count);
    end

    $display("generated=%0d delivered=%0d phantom=%0d overflow=%0d avg_latency=%0d max_latency=%0d jain_x1000=%0d",
      generated, delivered, phantom_count, score.overflow_count, score.avg_latency(0), score.max_lat, score.jain_fairness_x1000(0));

    if (error_count == 0)
      $display("CLUSTER4_CORRECTNESS_PASS");
    else
      $display("CLUSTER4_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
