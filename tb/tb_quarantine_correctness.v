// quarantine buffer 정확성 검증. arrival(펄스) 기반, cluster_buf류(§44) 테스트벤치와
// 같은 방법론 -- shadow_cnt로 "진짜 있어야 할 대기량"을 소스별로 추적(포화 없음, 정수
// 카운트)하고, 매 grant/overrun을 그것과 대조. overrun은 combinational이라 엣지 전에
// 샘플링(§44에서 배운 타이밍 함정 반영).
`timescale 1ns/1ps
module tb_quarantine_correctness;
  parameter CYCLES = 50000;
  parameter ARRIVAL_PCT = 15;
  parameter DRAIN_CYCLES = 300;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_quarantine #(.Q(4)) dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 31;
  integer cyc, i, c, draw, idx, phantom_count, error_count;
  integer generated, delivered, dropped_overrun;
  integer shadow_cnt [0:15]; // 소스별 "진짜 밀려있어야 할 개수"(포화 없음)

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (shadow_cnt[idx] <= 0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM cyc=%0d idx=%0d", cyc, idx);
            end else begin
              delivered = delivered + 1;
              shadow_cnt[idx] = shadow_cnt[idx] - 1;
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0;
    for (i = 0; i < 16; i = i + 1) shadow_cnt[i] = 0;
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
      #1; // overrun은 combinational -- 엣지 전, arrival 안정 시점에 샘플링.
      for (i = 0; i < 16; i = i + 1) begin
        if (overrun_w[i]) dropped_overrun = dropped_overrun + 1;
        else if (arrival[i]) shadow_cnt[i] = shadow_cnt[i] + 1; // 진짜로 받아들여진 도착만 카운트
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

    $display("generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d",
      generated, delivered, dropped_overrun, phantom_count);
    if (error_count == 0) $display("QUARANTINE_CORRECTNESS_PASS");
    else $display("QUARANTINE_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
