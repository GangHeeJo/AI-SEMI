// cluster2_steal_buf_pipe(파이프라인 버전) 정확성 검증 -- tb_steal_buf_correctness.v와
// 동일 방법론이되, was_overrun 스냅샷 버그(§63에서 발견)를 처음부터 반영. 파이프라인
// 때문에 지연이 늘었지만 arrival이 폐루프가 아니라 매 사이클 독립 펄스라 TB 쪽엔
// 영향 없음(§64 논의) -- DUT 내부의 just_granted_row 하자드 방지 로직이 실제로
// 맞는지를 이 테스트가 검증함.
`timescale 1ns/1ps
module tb_steal_buf_pipe_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_pipe dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 41;
  integer cyc, i, c, draw, idx;
  integer generated, delivered, dropped_overrun, phantom_count, error_count, collision_count;

  reg [1:0] shadow_cnt [0:15];
  reg was_overrun [0:15];

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
      #1;
      for (i = 0; i < 16; i = i + 1) begin
        was_overrun[i] = 1'b0;
        if (overrun_w[i]) begin
          dropped_overrun = dropped_overrun + 1;
          was_overrun[i] = 1'b1;
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
        if (arrival[i] && !was_overrun[i])
          shadow_cnt[i] = shadow_cnt[i] + 2'd1;
      end
    end

    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + 3000; cyc = cyc + 1) begin
      @(posedge clk); #1;
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
    if (error_count == 0) $display("STEAL_BUF_PIPE_CORRECTNESS_PASS");
    else $display("STEAL_BUF_PIPE_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
