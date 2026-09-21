`timescale 1ns/1ps
// Digital 2차 top-level v2(predictor 통합) 실트래픽 검증. rtl/bayes_filter.v는 §133에서 이미
// 이벤트 단위로 오라클과 bit-exact 검증됐고, aer_tx16_coord_transform_v1은 §113~115에서
// 좌표변환+world_mem 정확성이 검증됐음 -- 이 테스트벤치는 그 둘을 이어붙인 v2의 **배선/프론트엔드
// 자체**가 맞는지만 확인한다:
//   (1) 보존식 -- generated(도착한 비트 수) = consumed(predictor로 들어간 이벤트 수) + overrun
//   (2) 프론트엔드가 predictor에 넘긴 (row,col,pol) 시퀀스를 그대로 기록해뒀다가, 별도의
//       독립 bayes_filter 인스턴스에 똑같은 순서로 먹여서 매 이벤트 theta_out이 v2 안의
//       predictor가 실제로 낸 theta_out과 정확히 일치하는지(배선 자체에 비트 스왑 등 결함이
//       없는지) -- 순서대로 재생하므로 두 인스턴스는 항상 같은 입력 이력을 갖고, 결정적으로
//       같은 출력이 나와야 함.
// 실시간 처리량(초당 이벤트) 대비 predictor가 이벤트당 ~600사이클이 걸리는 구조적 병목은
// 이번 실측으로 정직하게 드러내는 게 목적이지, 여기서 고치는 게 목적이 아님(progress.md 참고).
module tb_aer_tx16_coord_transform_v2_uzh_trace;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  wire [15:0] overrun, pred_overrun;
  wire [7:0]  wmem_overrun;
  wire [7:0]  theta_idx_out;
  wire        world_we;
  wire [11:0] world_addr;
  wire        world_pol;

  aer_tx16_coord_transform_v2 dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .overrun(overrun), .wmem_overrun(wmem_overrun), .pred_overrun(pred_overrun),
    .theta_idx_out(theta_idx_out),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );

  always #5 clk = ~clk;

  // 프론트엔드가 predictor에 실제로 넘긴 이벤트, 그리고 predictor가 실제로 낸 theta_out을
  // 순서대로 기록 -- 재생용 독립 bayes_filter와의 대조에 씀
  reg [1:0] rec_row [0:20000];
  reg [1:0] rec_col [0:20000];
  reg       rec_pol [0:20000];
  reg [7:0] live_theta [0:20000];
  integer   consumed, live_idx;

  integer generated, overrun_total;
  integer i;

  always @(posedge clk) begin
    if (dut.win_valid) begin
      rec_row[consumed] = dut.win_idx[3:2];
      rec_col[consumed] = dut.win_idx[1:0];
      rec_pol[consumed] = dut.pending_pol[dut.win_idx];
      consumed = consumed + 1;
    end
    if (dut.u_bf.valid_out) begin
      live_theta[live_idx] = dut.u_bf.theta_out;
      live_idx = live_idx + 1;
    end
    for (i = 0; i < 16; i = i + 1) begin
      if (arrival[i]) generated = generated + 1;
      if (pred_overrun[i]) overrun_total = overrun_total + 1;
    end
  end

  integer fd_ev, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer cyc;

  // 재생용 독립 bayes_filter -- v2 안의 predictor와 완전히 분리된 인스턴스
  reg  replay_valid_in, replay_pol_in;
  reg  [1:0] replay_row_in, replay_col_in;
  wire replay_busy, replay_valid_out;
  wire [7:0] replay_theta_out;
  bayes_filter_v1 u_replay (
    .clk(clk), .rst(rst),
    .valid_in(replay_valid_in), .row_in(replay_row_in), .col_in(replay_col_in), .pol_in(replay_pol_in),
    .busy(replay_busy), .valid_out(replay_valid_out), .theta_out(replay_theta_out)
  );

  integer replay_idx, replay_mismatches;
  task automatic replay_issue;
    begin
      @(posedge clk); #1;
      while (replay_busy) begin @(posedge clk); #1; end
      replay_row_in = rec_row[replay_idx]; replay_col_in = rec_col[replay_idx]; replay_pol_in = rec_pol[replay_idx];
      replay_valid_in = 1'b1;
      @(posedge clk); #1;
      replay_valid_in = 1'b0;
      while (!replay_valid_out) begin @(posedge clk); #1; end
      if (replay_theta_out !== live_theta[replay_idx]) begin
        replay_mismatches = replay_mismatches + 1;
        if (replay_mismatches <= 5)
          $display("REPLAY_MISMATCH idx=%0d expected(live)=%0d got(replay)=%0d",
                    replay_idx, live_theta[replay_idx], replay_theta_out);
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    generated = 0; overrun_total = 0; consumed = 0; live_idx = 0;
    replay_valid_in = 0; replay_row_in = 0; replay_col_in = 0; replay_pol_in = 0;
    replay_mismatches = 0;

    fd_ev = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt", "r");
    if (fd_ev == 0) begin $display("CANNOT_OPEN_ADDRPOL"); $finish; end
    scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);

    @(posedge clk); #1; rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0; polarity_in = 16'd0;
      if (have_next && next_cycle == cyc) begin
        arrival = next_addr[15:0];
        polarity_in = next_pol[15:0];
        scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      @(posedge clk); #1;
      cyc = cyc + 1;
    end
    $fclose(fd_ev);

    // predictor가 밀린 pending을 마저 비울 시간을 넉넉히 줌(§133 기준 이벤트당 최대 ~800사이클)
    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 600000; i = i + 1) begin
      @(posedge clk); #1;
    end

    $display("generated=%0d consumed=%0d overrun=%0d (conservation: %0s)",
              generated, consumed, overrun_total,
              (generated == consumed + overrun_total) ? "OK" : "FAIL");

    for (replay_idx = 0; replay_idx < consumed; replay_idx = replay_idx + 1)
      replay_issue;

    $display("replay_checked=%0d replay_mismatches=%0d", consumed, replay_mismatches);
    if (consumed > 0 && replay_mismatches == 0 && generated == (consumed + overrun_total))
      $display("AER_TX16_COORD_TRANSFORM_V2_WIRING_PASS");
    else
      $display("AER_TX16_COORD_TRANSFORM_V2_WIRING_FAIL");
    $finish;
  end
endmodule
