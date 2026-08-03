// 재사용 가능한 채점기(scoreboard) 모듈 — 셀별 밀린 이벤트 큐, 지연시간(평균/최악),
// Jain's fairness index를 계산한다. 그동안 테스트벤치마다 복사-붙여넣기 해온
// "큐 추적 + 통계" 로직을 하나로 통일하기 위해 만듦(친구 팀원의 aer_scoreboard.sv
// 구조를 참고 — 모듈로 만들어야 한 테스트벤치 안에서 DUT 두 개(예: v2 vs v3)를
// 비교할 때 스코어보드도 두 개(u_score1, u_score2)를 독립적으로 찍어낼 수 있음.
//
// 사용 예:
//   event_scoreboard #(.N(16)) u_score();
//   initial u_score.init;
//   ... u_score.record_arrival(idx, cyc);
//   ... latency = u_score.record_departure(idx, cyc); // 밀린 게 없으면 -1(phantom)
//   $display(..., u_score.avg_latency(0), u_score.max_lat, u_score.jain_fairness_x1000(0));
// 셀별 통계가 필요하면 u_score.visits[idx](방문횟수), u_score.lat_sum_by_idx[idx](누적지연)를
// 직접 읽으면 됨 — center/periphery 같은 그룹 집계는 실험마다 다르니 모듈 밖에서 처리.
module event_scoreboard #(
  parameter N = 16,
  parameter QDEPTH = 64
) ();
  integer queue [0:N-1][0:QDEPTH-1];
  integer qhead [0:N-1];
  integer qcount [0:N-1];
  integer visits [0:N-1];
  integer lat_sum_by_idx [0:N-1];
  integer sum_lat;
  integer count;
  integer max_lat;
  integer overflow_count;

  task init;
    integer i;
    begin
      sum_lat = 0;
      count = 0;
      max_lat = 0;
      overflow_count = 0;
      for (i = 0; i < N; i = i + 1) begin
        qhead[i] = 0;
        qcount[i] = 0;
        visits[i] = 0;
        lat_sum_by_idx[i] = 0;
      end
    end
  endtask

  // 큐가 가득 찼으면 이벤트를 버리고 overflow_count만 올린다(원래 도착 로직과 동일).
  task record_arrival;
    input integer idx;
    input integer cyc;
    begin
      if (qcount[idx] < QDEPTH) begin
        queue[idx][(qhead[idx] + qcount[idx]) % QDEPTH] = cyc;
        qcount[idx] = qcount[idx] + 1;
      end else begin
        overflow_count = overflow_count + 1;
      end
    end
  endtask

  // idx에 밀린 이벤트가 있으면 발화 처리하고 지연시간을 리턴, 없으면 -1(phantom).
  function integer record_departure;
    input integer idx;
    input integer cyc;
    integer latency;
    begin
      if (qcount[idx] > 0) begin
        latency = cyc - queue[idx][qhead[idx]];
        qhead[idx] = (qhead[idx] + 1) % QDEPTH;
        qcount[idx] = qcount[idx] - 1;
        sum_lat = sum_lat + latency;
        count = count + 1;
        if (latency > max_lat) max_lat = latency;
        visits[idx] = visits[idx] + 1;
        lat_sum_by_idx[idx] = lat_sum_by_idx[idx] + latency;
        record_departure = latency;
      end else begin
        record_departure = -1;
      end
    end
  endfunction

  // Verilog-2001 함수는 입력 포트가 최소 1개 필요해서 더미 인자를 둠(사용 안 함).
  function integer avg_latency;
    input integer unused;
    begin
      if (count > 0) avg_latency = sum_lat / count;
      else avg_latency = 0;
    end
  endfunction

  // Jain's fairness index: (합)^2 / (N * 제곱합). 1000=완벽히 공평, 1000/N=최악.
  // 정수 나눗셈 손실을 피하려고 0~1000 정수로 반환.
  function integer jain_fairness_x1000;
    input integer unused;
    integer j;
    real jsum, jsq;
    begin
      jsum = 0.0;
      jsq = 0.0;
      for (j = 0; j < N; j = j + 1) begin
        jsum = jsum + visits[j];
        jsq = jsq + visits[j] * visits[j];
      end
      if (jsq == 0.0) jain_fairness_x1000 = 1000;
      else jain_fairness_x1000 = (jsum * jsum * 1000.0) / (N * jsq);
    end
  endfunction
endmodule
