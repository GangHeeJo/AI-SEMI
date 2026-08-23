// 하이브리드+buf 결합(cluster2_buf 기반 재발화 생존 + bitmap 전환) 정확성 검증.
// tb_cluster2_buf_correctness.v와 동일 방법론(arrival 펄스, shadow_cnt 2-deep 포화,
// overrun 엣지 전 스냅샷) + mode/bitmap 드레인 추가. 재발화 스트레스 구간도 포함해서
// buf의 재발화 생존이 bitmap 추가 후에도 유지되는지 직접 확인.
`timescale 1ns/1ps
module tb_hybrid_buf_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire mode_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;
  wire [15:0] bitmap_w;

  aer_tx16_hybrid_cluster2_buf_bitmap dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .mode(mode_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1),
    .bitmap(bitmap_w));

  always #5 clk = ~clk;

  integer rng_seed = 41;
  integer cyc, i, c, draw, idx;
  integer generated, delivered, dropped_overrun, phantom_count, error_count, collision_count;
  integer addressed_cycles, bitmap_cycles;

  reg [1:0] shadow_cnt [0:15];
  reg was_overrun [0:15];

  task automatic drain;
    begin
      if (mode_w) begin
        bitmap_cycles = bitmap_cycles + 1;
        for (c = 0; c < N; c = c + 1) begin
          if (bitmap_w[c]) begin
            if (shadow_cnt[c] == 2'd0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM(bitmap) cyc=%0d idx=%0d", cyc, c);
            end else begin
              delivered = delivered + 1;
              shadow_cnt[c] = shadow_cnt[c] - 2'd1;
            end
          end
        end
      end else begin
        addressed_cycles = addressed_cycles + 1;
        if (valid0 && valid1 && (row0 == row1)) begin
          collision_count = collision_count + 1;
          error_count = error_count + 1;
          $display("LANE_COLLISION cyc=%0d row=%0d", cyc, row0);
        end
        if (valid0) begin
          for (c = 0; c < 4; c = c + 1) begin
            if (col_mask0[c]) begin
              idx = row0*4 + c;
              if (shadow_cnt[idx] == 2'd0) begin
                phantom_count = phantom_count + 1;
                error_count = error_count + 1;
                $display("PHANTOM(c2-0) cyc=%0d idx=%0d", cyc, idx);
              end else begin
                delivered = delivered + 1;
                shadow_cnt[idx] = shadow_cnt[idx] - 2'd1;
              end
            end
          end
        end
        if (valid1) begin
          for (c = 0; c < 4; c = c + 1) begin
            if (col_mask1[c]) begin
              idx = row1*4 + c;
              if (shadow_cnt[idx] == 2'd0) begin
                phantom_count = phantom_count + 1;
                error_count = error_count + 1;
                $display("PHANTOM(c2-1) cyc=%0d idx=%0d", cyc, idx);
              end else begin
                delivered = delivered + 1;
                shadow_cnt[idx] = shadow_cnt[idx] - 2'd1;
              end
            end
          end
        end
      end
    end
  endtask

  task automatic run_random_phase;
    input integer arrival_pct;
    input integer n_cycles;
    begin
      for (cyc = 0; cyc < n_cycles; cyc = cyc + 1) begin
        arrival = 16'd0;
        for (i = 0; i < 16; i = i + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < arrival_pct) begin
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
        drain;
        for (i = 0; i < 16; i = i + 1) begin
          if (arrival[i] && !was_overrun[i])
            shadow_cnt[i] = shadow_cnt[i] + 2'd1;
        end
      end
    end
  endtask

  // 재발화 스트레스: 소스 0이 매 사이클 연속 재발화(retrigger 트레이스와 동일 패턴).
  task automatic run_retrigger_stress;
    input integer n_cycles;
    begin
      for (cyc = 0; cyc < n_cycles; cyc = cyc + 1) begin
        arrival = 16'd0;
        arrival[0] = 1'b1;
        generated = generated + 1;
        #1;
        was_overrun[0] = 1'b0;
        if (overrun_w[0]) begin
          dropped_overrun = dropped_overrun + 1;
          was_overrun[0] = 1'b1;
        end
        @(posedge clk); #1;
        drain;
        if (arrival[0] && !was_overrun[0])
          shadow_cnt[0] = shadow_cnt[0] + 2'd1;
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0; collision_count = 0;
    addressed_cycles = 0; bitmap_cycles = 0;
    for (i = 0; i < 16; i = i + 1) shadow_cnt[i] = 2'd0;
    @(posedge clk); #1;
    rst = 0;

    run_random_phase(ARRIVAL_PCT, CYCLES);

    $display("[random ARRIVAL_PCT=%0d] generated=%0d delivered=%0d dropped_overrun=%0d addr_cyc=%0d bm_cyc=%0d",
      ARRIVAL_PCT, generated, delivered, dropped_overrun, addressed_cycles, bitmap_cycles);

    // 재발화 스트레스 구간 -- 별도로 손실을 집계하기 위해 카운터 스냅샷.
    begin : retrig
      integer gen_before, drop_before;
      gen_before = generated; drop_before = dropped_overrun;
      run_retrigger_stress(2000);
      $display("[retrigger stress 2000cyc] generated=%0d dropped_overrun=%0d survival_rate=%0d.%0d%%",
        generated - gen_before, dropped_overrun - drop_before,
        ((generated-gen_before-(dropped_overrun-drop_before))*100)/(generated-gen_before),
        (((generated-gen_before-(dropped_overrun-drop_before))*1000)/(generated-gen_before))%10);
    end

    arrival = 16'd0;
    for (cyc = 0; cyc < 2000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain;
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

    $display("TOTAL generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d collisions=%0d",
      generated, delivered, dropped_overrun, phantom_count, collision_count);
    if (error_count == 0) $display("HYBRID_BUF_CORRECTNESS_PASS");
    else $display("HYBRID_BUF_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
