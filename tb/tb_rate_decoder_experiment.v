// interval/rate coding 실험 (수정판) -- 이전 버전의 오류(req를 V사이클 붙잡아두는
// 건 "이벤트 하나가 대기중"이지 "스파이크 V개"가 아님, phantom 버그 전례와 같은
// 종류의 실수)를 고쳐서, T=16cycle 윈도우 안에 V개의 "독립된" 이벤트로 값을
// 인코딩한다. fovea(무수정)와 이미 검증된 event_scoreboard를 그대로 재사용 --
// source5(중심행)에 V개의 개별 arrival을 뿌리고(도착 시점은 균등분산), 그 윈도우
// 동안 실제로 몇 개가 delivered됐는지 세서 V를 복원 시도한다.
`timescale 1ns/1ps
module tb_rate_decoder_experiment;
  parameter T_WINDOW = 16; // 인코딩 윈도우(cycle)
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid; wire [3:0] addr;

  aer_tx16_trad_rowcol_fovea #(.WEIGHT(5)) tx(
    .clk(clk), .rst(rst), .req(req), .valid(valid), .addr(addr));

  event_scoreboard #(.N(16), .QDEPTH(64)) score();

  always #5 clk = ~clk;

  integer cyc, i, draw;
  integer rng_seed = 99;
  integer V, delivered5, lat;
  integer trial, err_sum_uncontended, err_sum_contended, max_err_contended;
  integer errs_uncontended, errs_contended;
  integer spike_cycle [0:15]; // 이번 시행에서 소스5의 V개 스파이크가 몇 사이클째에 나는지

  // V개의 스파이크를 T_WINDOW 안에 최대한 균등하게 분산시킨 사이클 목록을 만든다.
  task automatic plan_spikes(input integer v);
    integer s;
    begin
      for (s = 0; s < v; s = s + 1)
        spike_cycle[s] = (s * T_WINDOW) / (v == 0 ? 1 : v);
    end
  endtask

  task automatic run_one_trial(input integer value, input integer contended, output integer delivered_val);
    integer next_spike;
    begin
      score.init;
      req = 16'd0;
      next_spike = 0;
      plan_spikes(value);

      for (cyc = 0; cyc < T_WINDOW; cyc = cyc + 1) begin
        // 소스5: 계획된 사이클에 도달하면 "독립된 이벤트 1개" 도착(이미 pending이면
        // 스킵 -- 우리 storage-free 모델에서 그건 overrun/유실이지 큰 값이 아님).
        if ((next_spike < value) && (cyc == spike_cycle[next_spike])) begin
          score.record_arrival(5, cyc);
          next_spike = next_spike + 1;
        end
        // 경합: 나머지 15개 소스도 각자 독립적으로 무작위 도착(고정 FFFF 패턴은
        // §37 영구기아 버그를 우연히 재현해서 순수 경합 효과 측정을 방해함).
        if (contended) begin
          for (i = 0; i < 16; i = i + 1) begin
            if (i != 5) begin
              draw = (($random(rng_seed) % 100 + 100) % 100);
              if (draw < 60) score.record_arrival(i, cyc);
            end
          end
        end
        for (i = 0; i < 16; i = i + 1)
          req[i] = (score.qcount[i] > 0);

        @(posedge clk); #1;

        if (valid) lat = score.record_departure(addr, cyc);
      end
      // 윈도우 종료 후 잔여분 배출(디코더가 "충분히 기다린 뒤" 셀 수 있게 몇 사이클 더).
      req = 16'd0;
      repeat (10) begin
        @(posedge clk); #1;
        if (valid) lat = score.record_departure(addr, cyc);
      end

      delivered_val = score.visits[5];
    end
  endtask

  initial begin
    rst = 1; req = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    err_sum_uncontended = 0; err_sum_contended = 0; max_err_contended = 0;
    errs_uncontended = 0; errs_contended = 0;

    $display("=== 무경합(소스5 혼자, T=%0d) ===", T_WINDOW);
    for (trial = 0; trial <= 15; trial = trial + 1) begin
      V = trial;
      run_one_trial(V, 0, delivered5);
      $display("V=%0d delivered=%0d err=%0d", V, delivered5, V-delivered5);
      err_sum_uncontended = err_sum_uncontended + (V-delivered5);
      if (V != delivered5) errs_uncontended = errs_uncontended + 1;
    end

    $display("=== 경합(나머지 15개 각자 무작위 60%%, T=%0d) ===", T_WINDOW);
    for (trial = 0; trial <= 15; trial = trial + 1) begin
      V = trial;
      run_one_trial(V, 1, delivered5);
      $display("V=%0d delivered=%0d err=%0d", V, delivered5, V-delivered5);
      err_sum_contended = err_sum_contended + (V-delivered5);
      if (V != delivered5) errs_contended = errs_contended + 1;
      if ((V-delivered5) > max_err_contended) max_err_contended = V-delivered5;
    end

    $display("무경합: 오차난 시행=%0d/16, 오차합=%0d", errs_uncontended, err_sum_uncontended);
    $display("경합:   오차난 시행=%0d/16, 오차합=%0d, 최대오차=%0d", errs_contended, err_sum_contended, max_err_contended);
    $finish;
  end
endmodule
