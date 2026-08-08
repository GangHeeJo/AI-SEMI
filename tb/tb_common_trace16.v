// 공통 이벤트 트레이스(scripts/gen_common_trace.py 생성) 기반 base 검증/성능측정.
// 팀 공통 포맷: arrival_cycle,source_index (N=16, source_index = row*4+col).
// +TRACE_FILE=path 플러스아그로 CSV 경로 지정.
//
// ack 갭 수정: aer_tx16의 새 captured[] 출력을 이용해, 캡처된 그 사이클에
// 바로 record_departure를 불러 req를 즉시 내린다(예전엔 RX의 event_valid를
// 기다렸는데, 그 사이 지연 동안 req가 안 내려가서 DUT가 같은 요청을 또
// 캡처해버리는 실제 버그가 있었음 — progress.md #11 참고).
// RX 출력은 별도로 "캡처 순서대로 제대로 배달됐는지"만 검증한다(delivery FIFO).
`timescale 1ns/1ps
module tb_common_trace16;
  parameter N = 16;
  parameter QDEPTH = 8;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire [1:0] captured_row;
  wire [3:0] captured_cols;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  aer_tx16 tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr),
              .captured_row(captured_row), .captured_cols(captured_cols));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer fd, r, cyc_field, src_field;
  integer cyc, i, idx, latency;
  integer phantom_errors, delivery_errors, max_cycle;
  integer pending_cyc [0:99999];
  integer pending_src [0:99999];
  integer pending_count, pending_head, accepted;
  integer expect_fifo [0:99999];
  integer expect_head, expect_tail;
  reg [1023:0] trace_path;
  reg [8191:0] line;

  initial begin
    if (!$value$plusargs("TRACE_FILE=%s", trace_path)) begin
      $display("ERROR: +TRACE_FILE=<path> 필요");
      $finish;
    end

    // CSV를 미리 전부 읽어 사이클순 이벤트 리스트로 저장(헤더 1줄 스킵)
    fd = $fopen(trace_path, "r");
    if (fd == 0) begin
      $display("ERROR: 트레이스 파일 열기 실패: %0s", trace_path);
      $finish;
    end
    r = $fgets(line, fd); // header skip
    pending_count = 0;
    max_cycle = 0;
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%d,%d\n", cyc_field, src_field);
      if (r == 2) begin
        pending_cyc[pending_count] = cyc_field;
        pending_src[pending_count] = src_field;
        if (cyc_field > max_cycle) max_cycle = cyc_field;
        pending_count = pending_count + 1;
      end
    end
    $fclose(fd);
    $display("트레이스 로드: %0s, 이벤트 %0d건, 최대 사이클 %0d", trace_path, pending_count, max_cycle);

    rst = 1; req = 16'd0; phantom_errors = 0; delivery_errors = 0;
    pending_head = 0; expect_head = 0; expect_tail = 0;
    score.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc <= max_cycle + 200; cyc = cyc + 1) begin
      while (pending_head < pending_count && pending_cyc[pending_head] == cyc) begin
        score.record_arrival(pending_src[pending_head], cyc);
        pending_head = pending_head + 1;
      end
      for (i = 0; i < N; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      // 캡처된 즉시 큐에서 빼서 req를 다음 사이클에 바로 반영(ack 대체).
      // captured_cols==0이면 이번 사이클엔 캡처 없음.
      for (i = 0; i < 4; i = i + 1) begin
        if (captured_cols[i]) begin
          idx = captured_row * 4 + i;
          latency = score.record_departure(idx, cyc);
          if (latency < 0) begin
            $display("PHANTOM ERROR: cycle=%0d idx=%0d (capture 시점)", cyc, idx);
            phantom_errors = phantom_errors + 1;
          end else begin
            expect_fifo[expect_tail] = idx;
            expect_tail = expect_tail + 1;
          end
        end
      end

      // RX 배달 검증: 캡처된 순서 그대로 나오는지만 확인(지연시간 통계는 위에서 이미 처리).
      if (event_valid) begin
        idx = event_row * 4 + event_col;
        if (expect_head >= expect_tail || expect_fifo[expect_head] != idx) begin
          $display("DELIVERY MISMATCH: cycle=%0d 받은 idx=%0d, 기대값=%0d", cyc, idx,
                    (expect_head < expect_tail) ? expect_fifo[expect_head] : -1);
          delivery_errors = delivery_errors + 1;
        end else begin
          expect_head = expect_head + 1;
        end
      end
    end

    // QDEPTH 초과분(overflow)은 실제 픽셀의 이벤트 손실과 동일한 정상 드롭이므로
    // pass 조건은 (trace 이벤트 수 - overflow) == emitted 여야 함.
    accepted = pending_count - score.overflow_count;
    $display("AER_METRICS trace=%0s trace_events=%0d accepted=%0d emitted=%0d dropped_overflow=%0d capture_errors=%0d delivery_errors=%0d avg_latency=%0d max_latency=%0d throughput_x1000=%0d fairness_jain_x1000=%0d",
              trace_path, pending_count, accepted, score.count, score.overflow_count, phantom_errors, delivery_errors,
              score.avg_latency(0), score.max_lat,
              (score.count*1000)/(max_cycle+1), score.jain_fairness_x1000(0));
    if (phantom_errors > 0 || delivery_errors > 0 || score.count != accepted)
      $display("=== 검증 실패: capture_errors=%0d delivery_errors=%0d accepted=%0d emitted=%0d ===",
                phantom_errors, delivery_errors, accepted, score.count);
    else
      $display("=== 검증 통과(드롭 %0d건은 QDEPTH=%0d 초과로 인한 정상 손실) ===", score.overflow_count, QDEPTH);
    $finish;
  end
endmodule
