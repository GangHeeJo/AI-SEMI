// cluster2_steal_buf 정확성 검증 -- tb_buf_correctness.v(§44)와 완전히 동일한 방법론
// (arrival 펄스, shadow_cnt 2-deep 포화, overrun은 엣지 전에 샘플링) + 두 레인이 같은
// 사이클에 같은 행을 가리키는 모순이 없는지(lane collision) 추가 확인.
`timescale 1ns/1ps
module tb_steal_buf_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 41;
  integer cyc, i, c, draw, idx;
  integer generated, delivered, dropped_overrun, phantom_count, error_count, collision_count;

  reg [1:0] shadow_cnt [0:15];

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (shadow_cnt[idx] == 2'd0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM cyc=%0d idx=%0d", cyc, idx);
            end else begin
              delivered = delivered + 1;
              shadow_cnt[idx] = shadow_cnt[idx] - 2'd1;
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0; collision_count = 0;
    for (i = 0; i < 16; i = i + 1) shadow_cnt[i] = 2'd0;
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
      #1; // overrun은 combinational -- 엣지 전, arrival 안정 시점에 샘플링(§44 교훈).
      for (i = 0; i < 16; i = i + 1) begin
        if (overrun_w[i]) begin
          dropped_overrun = dropped_overrun + 1;
          if (shadow_cnt[i] != 2'd2) begin
            error_count = error_count + 1;
            $display("BAD_OVERRUN_REPORT src=%0d shadow=%0d cyc=%0d", i, shadow_cnt[i], cyc);
          end
        end
      end

      @(posedge clk); #1;

      if (valid0 && valid1 && (row0 == row1)) begin
        collision_count = collision_count + 1;
        error_count = error_count + 1;
        $display("LANE_COLLISION cyc=%0d row=%0d", cyc, row0);
      end

      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);

      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && (shadow_cnt[i] != 2'd2))
          shadow_cnt[i] = shadow_cnt[i] + 2'd1;
      end
    end

    // drain: 새 도착 없이 남은 pending 다 뺀다.
    arrival = 16'd0;
    $display("PRE_DRAIN pending_gt0=%b center_idle=%b periph_idle=%b steal2p=%b steal2c=%b",
      dut.pending_gt0, dut.center_idle, dut.periph_idle, dut.steal_to_periph, dut.steal_to_center);
    for (cyc = CYCLES; cyc < CYCLES + 2000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (cyc < CYCLES + 10)
        $display("drain cyc=%0d pending_gt0=%b center_idle=%b periph_idle=%b steal2p=%b steal2c=%b cgnt=%b pgnt=%b v0=%b r0=%0d cm0=%b v1=%b r1=%0d cm1=%b",
          cyc, dut.pending_gt0, dut.center_idle, dut.periph_idle, dut.steal_to_periph, dut.steal_to_center,
          dut.center_gnt, dut.periph_gnt, valid0, row0, col_mask0, valid1, row1, col_mask1);
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
    end

    for (i = 0; i < 16; i = i + 1) begin
      if (shadow_cnt[i] != 0) begin
        error_count = error_count + 1;
        $display("DRAIN_INCOMPLETE source=%0d shadow_cnt=%0d", i, shadow_cnt[i]);
      end
    end
    if ((delivered + dropped_overrun) != generated) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH delivered=%0d dropped=%0d sum=%0d generated=%0d",
        delivered, dropped_overrun, delivered+dropped_overrun, generated);
    end

    $display("generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d collisions=%0d",
      generated, delivered, dropped_overrun, phantom_count, collision_count);
    if (error_count == 0) $display("STEAL_BUF_CORRECTNESS_PASS");
    else $display("STEAL_BUF_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
