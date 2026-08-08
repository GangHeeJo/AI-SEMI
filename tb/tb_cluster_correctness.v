// fovea_cluster의 기능 정확성 검증 -- lossy-admission(tb_lossy_admission.v)은 손실률만
// 쟀지 phantom/누락 여부는 안 봤음. 여기서는 QDEPTH를 사실상 무한(200000)으로 둬서
// 드롭이 안 일어나게 하고, "보낸 만큼 정확히 다 도착하는지"를 확인한다.
//
// 추가로 확인하는 것: col_mask 비트가 그 사이클에 진짜 pending이었던 열만 가리키는지
// (phantom), 같은 이벤트가 두 번 배출되지 않는지(qcount>0 조건으로 자연히 보장되지만
// 직접 카운트로 재확인), drain 후 generated==delivered인지.
`timescale 1ns/1ps
module tb_cluster_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 200000; // 사실상 무한 -- 손실 없이 정확성만 본다.
  parameter ARRIVAL_PCT = 15;
  parameter DRAIN_CYCLES = 5000;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid; wire [1:0] row; wire [3:0] col_mask;

  `ifndef WEIGHT_VAL
  `define WEIGHT_VAL 5
  `endif
  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(`WEIGHT_VAL)) dut(
    .clk(clk), .rst(rst), .req(req), .valid(valid), .row(row), .col_mask(col_mask));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, lat;
  integer generated, delivered, phantom_count, error_count;
  integer idx;

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

      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (score.qcount[idx] <= 0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM at cyc=%0d row=%0d col=%0d (idx=%0d) -- qcount was 0", cyc, row, c, idx);
            end else begin
              lat = score.record_departure(idx, cyc);
              delivered = delivered + 1;
            end
          end
        end
      end
    end

    // req를 전부 내려서 나머지도 자연 배출되게 하고 drain.
    req = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + DRAIN_CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1)
        req[i] = (score.qcount[i] > 0);
      @(posedge clk); #1;
      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (score.qcount[idx] <= 0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM(drain) at cyc=%0d row=%0d col=%0d (idx=%0d)", cyc, row, c, idx);
            end else begin
              lat = score.record_departure(idx, cyc);
              delivered = delivered + 1;
            end
          end
        end
      end
    end

    for (i = 0; i < N; i = i + 1) begin
      if (score.qcount[i] != 0) begin
        error_count = error_count + 1;
        $display("DRAIN_INCOMPLETE source=%0d qcount=%0d after %0d drain cycles", i, score.qcount[i], DRAIN_CYCLES);
      end
    end

    if (generated != delivered) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH generated=%0d delivered=%0d overflow=%0d", generated, delivered, score.overflow_count);
    end

    $display("generated=%0d delivered=%0d phantom=%0d overflow=%0d avg_latency=%0d max_latency=%0d jain_x1000=%0d",
      generated, delivered, phantom_count, score.overflow_count, score.avg_latency(0), score.max_lat, score.jain_fairness_x1000(0));

    if (error_count == 0)
      $display("CLUSTER_CORRECTNESS_PASS");
    else
      $display("CLUSTER_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
