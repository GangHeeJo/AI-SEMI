// cluster_buf 일반 정확성 검증 -- 무작위 도착(event_scoreboard, QDEPTH 사실상 무한)
// 상황에서 phantom/중복/카운트불일치가 없는지 확인. 2-deep을 넘는 도착은 회로가
// overrun으로 정직하게 보고해야 하고(유실 자체는 정상, §29와 같은 손실허용 철학),
// "유실 없이 배출된 것들"은 전부 정확해야 함.
`timescale 1ns/1ps
module tb_buf_correctness;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid; wire [1:0] row; wire [3:0] col_mask;

  aer_tx16_trad_rowcol_fovea_cluster_buf #(.WEIGHT(5)) dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid(valid), .row(row), .col_mask(col_mask));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, idx;
  integer generated, delivered, dropped_overrun, phantom_count, error_count;

  reg [1:0] shadow_cnt [0:15]; // 회로랑 별개로 직접 계산한 "진짜 있어야 할" 카운트

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0;
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
      // overrun은 combinational(arrival & pending_full)이라 엣지 전, arrival이
      // 이번 사이클 값으로 안정된 시점(지금)에 샘플링해야 함. 엣지 이후로 미루면
      // NBA가 이미 풀려서 pending_cnt가 다음 상태로 넘어간 뒤의 재평가값을 보게 됨
      // (버그였음 -- RTL이 아니라 이 샘플링 타이밍이 잘못됐던 것).
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

      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] == 2'd0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM src=%0d cyc=%0d", idx, cyc);
            end else begin
              delivered = delivered + 1;
            end
          end
        end
      end

      // shadow 갱신(회로랑 같은 규칙: 도착이면 +1(단, 이미 2면 무시=overrun 처리는 위에서 이미 셈),
      // 이번 사이클 grant된 열이면 -1).
      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && (shadow_cnt[i] != 2'd2))
          shadow_cnt[i] = shadow_cnt[i] + 2'd1;
      end
      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] != 2'd0) shadow_cnt[idx] = shadow_cnt[idx] - 2'd1;
          end
        end
      end
    end

    // drain: 더 이상 새 도착 없이 남은 pending을 다 뺀다.
    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + 100; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask[c]) begin
            idx = row*4 + c;
            if (shadow_cnt[idx] == 2'd0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
            end else begin
              delivered = delivered + 1;
              shadow_cnt[idx] = shadow_cnt[idx] - 2'd1;
            end
          end
        end
      end
    end

    $display("generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d",
      generated, delivered, dropped_overrun, phantom_count);
    if ((delivered + dropped_overrun) != generated) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH delivered+dropped=%0d generated=%0d", delivered+dropped_overrun, generated);
    end

    if (error_count == 0) $display("CLUSTER_BUF_CORRECTNESS_PASS");
    else $display("CLUSTER_BUF_CORRECTNESS_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
