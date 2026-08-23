// cluster2 cross-source timing fidelity (Ryu의 "AER induced motion artifact" 대응) 실측용 TB.
// 기존 avg_timing_error(같은 소스 내 연속 이벤트 간격 충실도)와 달리, 이건 "서로 다른 소스가
// 정확히 같은 사이클에 동시 발화했을 때, 실제 배달 사이클이 서로 얼마나 벌어지는가(spread)"를
// 잰다. spread=0이면 그 순간의 장면이 왜곡 없이 재구성됨을 뜻하고, spread>0이면 실제로는
// 동시에 일어난 사건이 서로 다른 시각에 읽혀서 재구성 영상이 일그러질 수 있다는 뜻.
`timescale 1ns/1ps
module tb_cluster2_crosssource_fidelity;
  parameter N = 16;
  parameter QDEPTH = 4096;
  parameter MAX_BATCHES = 64;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, idx, lat, arrival_cyc;
  integer generated, delivered, error_count;

  // -- batch(동시발화 묶음) 추적 --
  integer batch_active [0:MAX_BATCHES-1];
  integer batch_cyc    [0:MAX_BATCHES-1]; // injection cycle = batch id(sim 내내 고유값)
  integer batch_member [0:MAX_BATCHES-1][0:N-1];
  integer batch_ksize    [0:MAX_BATCHES-1];
  integer batch_recorded [0:MAX_BATCHES-1];
  integer batch_min_dep  [0:MAX_BATCHES-1];
  integer batch_max_dep  [0:MAX_BATCHES-1];

  integer new_batch_members [0:N-1];

  integer scen_spread_sum, scen_spread_count, scen_max_spread, scen_batches_done;

  task automatic batch_reset_all;
    integer b;
    begin
      for (b = 0; b < MAX_BATCHES; b = b + 1) batch_active[b] = 0;
    end
  endtask

  task automatic batch_start;
    input integer ksize;
    integer b, slot, s;
    begin
      slot = -1;
      for (b = 0; b < MAX_BATCHES; b = b + 1)
        if (!batch_active[b] && slot < 0) slot = b;
      if (slot < 0) begin
        $display("BATCH_SLOT_EXHAUSTED cyc=%0d", cyc);
        error_count = error_count + 1;
      end else begin
        batch_active[slot] = 1;
        batch_cyc[slot] = cyc;
        batch_ksize[slot] = ksize;
        batch_recorded[slot] = 0;
        batch_min_dep[slot] = 32'h7fffffff;
        batch_max_dep[slot] = -1;
        for (s = 0; s < N; s = s + 1)
          batch_member[slot][s] = new_batch_members[s];
      end
    end
  endtask

  task automatic try_record_departure_for_batches;
    input integer d_idx;
    input integer dep_cyc;
    input integer arr_cyc;
    integer b;
    begin
      for (b = 0; b < MAX_BATCHES; b = b + 1) begin
        if (batch_active[b] && batch_member[b][d_idx] && batch_cyc[b] == arr_cyc) begin
          batch_recorded[b] = batch_recorded[b] + 1;
          if (dep_cyc < batch_min_dep[b]) batch_min_dep[b] = dep_cyc;
          if (dep_cyc > batch_max_dep[b]) batch_max_dep[b] = dep_cyc;
          if (batch_recorded[b] == batch_ksize[b]) begin
            scen_spread_sum = scen_spread_sum + (batch_max_dep[b] - batch_min_dep[b]);
            scen_spread_count = scen_spread_count + 1;
            if ((batch_max_dep[b] - batch_min_dep[b]) > scen_max_spread)
              scen_max_spread = batch_max_dep[b] - batch_min_dep[b];
            scen_batches_done = scen_batches_done + 1;
            batch_active[b] = 0;
          end
        end
      end
    end
  endtask

  task automatic drain_lane;
    input integer valid_in;
    input integer row_in;
    input [3:0] mask_in;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (score.qcount[idx] <= 0) begin
              error_count = error_count + 1;
              $display("PHANTOM at cyc=%0d row=%0d col=%0d idx=%0d", cyc, row_in, c, idx);
            end else begin
              lat = score.record_departure(idx, cyc);
              delivered = delivered + 1;
              arrival_cyc = cyc - lat;
              try_record_departure_for_batches(idx, cyc, arrival_cyc);
            end
          end
        end
      end
    end
  endtask

  task automatic step_cycle;
    integer s;
    begin
      for (s = 0; s < N; s = s + 1) req[s] = (score.qcount[s] > 0);
      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0);
      drain_lane(valid1, row1, col_mask1);
      cyc = cyc + 1;
    end
  endtask

  // 모든 소스 큐가 빌 때까지 step. 버그로 인한 무한루프 방지용 세이프티 캡 포함.
  task automatic run_until_drained;
    integer s, busy, guard;
    begin
      busy = 1; guard = 0;
      while (busy && guard < 100000) begin
        step_cycle;
        guard = guard + 1;
        busy = 0;
        for (s = 0; s < N; s = s + 1) if (score.qcount[s] > 0) busy = 1;
      end
      if (guard >= 100000) begin
        $display("DRAIN_TIMEOUT cyc=%0d", cyc);
        error_count = error_count + 1;
      end
    end
  endtask

  task automatic inject_members_and_start_batch;
    integer s, ksize;
    begin
      ksize = 0;
      for (s = 0; s < N; s = s + 1) begin
        if (new_batch_members[s]) begin
          generated = generated + 1;
          score.record_arrival(s, cyc);
          ksize = ksize + 1;
        end
      end
      batch_start(ksize);
    end
  endtask

  task automatic clear_members;
    integer s;
    begin
      for (s = 0; s < N; s = s + 1) new_batch_members[s] = 0;
    end
  endtask

  task automatic report_scenario;
    input [39*8:1] label;
    begin
      if (scen_spread_count > 0)
        $display("SCEN=%0s batches=%0d avg_spread=%0d.%0d max_spread=%0d",
          label, scen_batches_done,
          scen_spread_sum / scen_spread_count,
          (scen_spread_sum * 10 / scen_spread_count) % 10,
          scen_max_spread);
      else
        $display("SCEN=%0s batches=0 (no data)", label);
    end
  endtask

  initial begin
    rst = 1; req = 16'd0;
    generated = 0; delivered = 0; error_count = 0;
    cyc = 0;
    score.init;
    batch_reset_all;
    @(posedge clk); #1;
    rst = 0;

    // ---- 시나리오 A: 같은 행(row) 안 4열 동시발화 -- cluster2 row-bitmap이면 spread=0 기대 ----
    scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
    for (i = 0; i < 4; i = i + 1) begin
      clear_members;
      new_batch_members[i*4+0] = 1; new_batch_members[i*4+1] = 1;
      new_batch_members[i*4+2] = 1; new_batch_members[i*4+3] = 1;
      inject_members_and_start_batch;
      run_until_drained;
    end
    report_scenario("A_same_row_4col");

    // ---- 시나리오 B: 같은 레인(중심 or 주변) 안 서로 다른 행 2개 동시발화 -- 실중재 발생 ----
    scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
    for (i = 0; i < 20; i = i + 1) begin
      clear_members;
      new_batch_members[4] = 1; new_batch_members[8] = 1; // row1 col0(중심) vs row2 col0(중심)
      inject_members_and_start_batch;
      run_until_drained;
      clear_members;
      new_batch_members[0] = 1; new_batch_members[12] = 1; // row0 col0(주변) vs row3 col0(주변)
      inject_members_and_start_batch;
      run_until_drained;
    end
    report_scenario("B_same_lane_cross_row");

    // ---- 시나리오 C: 다른 레인(중심 1개 + 주변 1개) 동시발화 -- 레인 독립이면 spread=0 기대 ----
    scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
    for (i = 0; i < 20; i = i + 1) begin
      clear_members;
      new_batch_members[4] = 1;  // row1(중심)
      new_batch_members[0] = 1;  // row0(주변)
      inject_members_and_start_batch;
      run_until_drained;
    end
    report_scenario("C_cross_lane");

    // ---- 시나리오 D: 최악조합 -- 중심쌍+주변쌍 4개가 한 사이클에 동시발화(배경부하 0) ----
    scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
    for (i = 0; i < 30; i = i + 1) begin
      clear_members;
      new_batch_members[4] = 1; new_batch_members[8] = 1;   // 중심 row1 vs row2
      new_batch_members[0] = 1; new_batch_members[12] = 1;  // 주변 row0 vs row3
      inject_members_and_start_batch;
      run_until_drained;
    end
    report_scenario("D_worst_isolated_k4");

    // ---- 시나리오 E: 시나리오 D의 4-버스트를 배경부하 위에서 주기적으로 반복 -- Ryu의
    //      event-rate vs timestamp-error 그래프와 같은 형태로, 배경부하를 스윕한다.
    //      (무제한 깊이 FIFO 모델 -- 우리 자체 event_scoreboard 방식)
    begin : sweep_e
      integer bg, s2, draw2, total_cyc, burst_period, next_burst, e, busy2, guard2;
      integer bg_levels [0:6];
      bg_levels[0] = 0; bg_levels[1] = 5; bg_levels[2] = 15; bg_levels[3] = 30;
      bg_levels[4] = 35; bg_levels[5] = 40; bg_levels[6] = 50;
      total_cyc = 2000;
      burst_period = 40;
      for (e = 0; e < 7; e = e + 1) begin
        bg = bg_levels[e];
        scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
        batch_reset_all;
        next_burst = cyc + burst_period;
        for (i = 0; i < total_cyc; i = i + 1) begin
          for (s2 = 0; s2 < N; s2 = s2 + 1) begin
            draw2 = (($random(rng_seed) % 100 + 100) % 100);
            if (draw2 < bg) begin
              generated = generated + 1;
              score.record_arrival(s2, cyc);
            end
          end
          if (cyc >= next_burst) begin
            clear_members;
            new_batch_members[4] = 1; new_batch_members[8] = 1;
            new_batch_members[0] = 1; new_batch_members[12] = 1;
            inject_members_and_start_batch;
            next_burst = cyc + burst_period;
          end
          step_cycle;
        end
        // 꼬리 drain: 아직 안 끝난 batch/큐가 있으면 마저 흘려보냄
        busy2 = 1; guard2 = 0;
        while (busy2 && guard2 < 100000) begin
          step_cycle;
          guard2 = guard2 + 1;
          busy2 = 0;
          for (s2 = 0; s2 < N; s2 = s2 + 1) if (score.qcount[s2] > 0) busy2 = 1;
        end
        report_scenario(bg == 0 ? "E_bg000" : bg == 5 ? "E_bg005" :
          bg == 15 ? "E_bg015" : bg == 30 ? "E_bg030" : bg == 35 ? "E_bg035" :
          bg == 40 ? "E_bg040" : "E_bg050");
      end
    end

    // ---- 시나리오 F: E와 완전히 동일하되, 공용 하네스(aer_clean_tb.sv)와 같은
    //      "소스당 1-entry, 이미 pending이면 새 발화는 즉시 overrun/드롭" 모델로 재실행.
    //      우리 자체 무제한 FIFO 모델(E)과 비교해서, E의 폭발이 DUT 문제인지 우리
    //      테스트벤치 모델링(무제한 큐 가정) 문제인지 가른다.
    begin : sweep_f
      integer bg, s2, draw2, total_cyc, burst_period, next_burst, e, busy2, guard2;
      integer bg_levels [0:6];
      integer ksize_f, m, member_idx;
      integer fixed_members [0:3];
      fixed_members[0] = 4; fixed_members[1] = 8; fixed_members[2] = 0; fixed_members[3] = 12;
      bg_levels[0] = 0; bg_levels[1] = 5; bg_levels[2] = 15; bg_levels[3] = 30;
      bg_levels[4] = 35; bg_levels[5] = 40; bg_levels[6] = 50;
      total_cyc = 2000;
      burst_period = 40;
      for (e = 0; e < 7; e = e + 1) begin
        bg = bg_levels[e];
        scen_spread_sum = 0; scen_spread_count = 0; scen_max_spread = 0; scen_batches_done = 0;
        batch_reset_all;
        next_burst = cyc + burst_period;
        for (i = 0; i < total_cyc; i = i + 1) begin
          for (s2 = 0; s2 < N; s2 = s2 + 1) begin
            if (score.qcount[s2] == 0) begin
              draw2 = (($random(rng_seed) % 100 + 100) % 100);
              if (draw2 < bg) begin
                generated = generated + 1;
                score.record_arrival(s2, cyc);
              end
            end
          end
          if (cyc >= next_burst) begin
            clear_members;
            ksize_f = 0;
            for (m = 0; m < 4; m = m + 1) begin
              member_idx = fixed_members[m];
              if (score.qcount[member_idx] == 0) begin
                new_batch_members[member_idx] = 1;
                generated = generated + 1;
                score.record_arrival(member_idx, cyc);
                ksize_f = ksize_f + 1;
              end
            end
            if (ksize_f > 0) batch_start(ksize_f);
            next_burst = cyc + burst_period;
          end
          step_cycle;
        end
        busy2 = 1; guard2 = 0;
        while (busy2 && guard2 < 100000) begin
          step_cycle;
          guard2 = guard2 + 1;
          busy2 = 0;
          for (s2 = 0; s2 < N; s2 = s2 + 1) if (score.qcount[s2] > 0) busy2 = 1;
        end
        report_scenario(bg == 0 ? "F_bg000" : bg == 5 ? "F_bg005" :
          bg == 15 ? "F_bg015" : bg == 30 ? "F_bg030" : bg == 35 ? "F_bg035" :
          bg == 40 ? "F_bg040" : "F_bg050");
      end
    end

    if (generated != delivered) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH generated=%0d delivered=%0d", generated, delivered);
    end

    if (error_count == 0)
      $display("CROSSSOURCE_FIDELITY_PASS");
    else
      $display("CROSSSOURCE_FIDELITY_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
