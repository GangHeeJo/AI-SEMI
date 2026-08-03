// 적응형(A-FAER)이 "물체가 실시간으로 움직일 때" 실제로 따라가는지 검증.
// 한 번의 실행 안에서 핫스팟 위치를 3단계로 바꾼다: 중심(0~1499) → 모서리(1500~2999)
// → 다시 중심(3000~4499). 각 전환 시점 이후 (1) hot_mask가 새 핫스팟에 맞게 재분류되기까지
// 몇 사이클 걸리는지 (2) 전환 직후 지연시간이 튀었다가 안정되는 모습을 측정한다.
module tb_moving_hotspot;
  `ifndef PHASE_LEN_VAL
  `define PHASE_LEN_VAL 400
  `endif
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 30;
  parameter PHASE_LEN = `PHASE_LEN_VAL;
  parameter TOTAL_CYCLES = PHASE_LEN * 3;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;
  wire       event_valid;
  wire [1:0] event_row, event_col;

  `ifndef DECAY_SHIFT_VAL
  `define DECAY_SHIFT_VAL 6
  `endif
  aer_tx16_adaptive #(.DECAY_SHIFT(`DECAY_SHIFT_VAL)) tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx16 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  integer cyc, i, idx, latency, phase;

  // phase 0,2 = 중심(5,6,9,10) hot / phase 1 = 모서리(0,3,12,15) hot
  function integer current_hotspot_idx(input integer c);
    if ((c/PHASE_LEN) % 2 == 0) current_hotspot_idx = 0; // 중심 단계
    else current_hotspot_idx = 1; // 모서리 단계
  endfunction

  function is_hotspot(input integer idx_, input integer ph);
    if (ph == 0) is_hotspot = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
    else is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15);
  endfunction

  // 각 단계별 "올바른" hot_mask (행 기준: 중심=행1,2 / 모서리=행0,3)
  function [3:0] expected_hot_mask(input integer ph);
    if (ph == 0) expected_hot_mask = 4'b0110;
    else expected_hot_mask = 4'b1001;
  endfunction

  integer transition_cycle [0:2]; // 각 phase 시작 사이클
  integer settle_cycle [0:2];     // hot_mask가 "지속적으로" 올바르게 안정된 사이클(-1=아직 못 찾음)
  integer match_streak [0:2];     // 연속으로 정답과 일치한 횟수
  integer match_count [0:2];      // 그 phase 안에서 정답과 일치한 총 사이클 수
  integer phase_cycle_count [0:2];
  localparam SETTLE_THRESHOLD = 20; // 이만큼 연속으로 맞아야 "안정됐다"고 인정
  integer last_phase;

  initial begin
    rst = 1; req = 16'd0;
    score.init;
    transition_cycle[0]=0; transition_cycle[1]=PHASE_LEN; transition_cycle[2]=PHASE_LEN*2;
    settle_cycle[0]=-1; settle_cycle[1]=-1; settle_cycle[2]=-1;
    match_streak[0]=0; match_streak[1]=0; match_streak[2]=0;
    match_count[0]=0; match_count[1]=0; match_count[2]=0;
    phase_cycle_count[0]=0; phase_cycle_count[1]=0; phase_cycle_count[2]=0;
    last_phase = -1;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < TOTAL_CYCLES; cyc = cyc + 1) begin
      phase = current_hotspot_idx(cyc);
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i,phase) ? HOT_PCT : BG_PCT)) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      `ifdef TRACE_PHASE1
      if (cyc >= PHASE_LEN && cyc < PHASE_LEN*2)
        $display("TRACE cyc=%0d hot_mask=%b activity=[%0d,%0d,%0d,%0d] rowpc=[%0d,%0d,%0d,%0d]",
          cyc, tx.hot_mask, tx.activity[0], tx.activity[1], tx.activity[2], tx.activity[3],
          tx.row_pending_cnt[0], tx.row_pending_cnt[1], tx.row_pending_cnt[2], tx.row_pending_cnt[3]);
      `endif

      begin : settle_check
        integer ph_idx;
        ph_idx = cyc/PHASE_LEN;
        phase_cycle_count[ph_idx] = phase_cycle_count[ph_idx] + 1;
        if (tx.hot_mask == expected_hot_mask(phase)) begin
          match_streak[ph_idx] = match_streak[ph_idx] + 1;
          match_count[ph_idx] = match_count[ph_idx] + 1;
          if (settle_cycle[ph_idx] == -1 && match_streak[ph_idx] >= SETTLE_THRESHOLD)
            settle_cycle[ph_idx] = cyc - transition_cycle[ph_idx] - SETTLE_THRESHOLD + 1;
        end else begin
          match_streak[ph_idx] = 0;
        end
      end

      if (event_valid) begin
        idx = event_row*4+event_col;
        latency = score.record_departure(idx, cyc);
      end
    end

    $display("=== 전환 후 hot_mask가 %0d사이클 연속으로 올바르게 안정되기까지 걸린 시간 + 그 phase 동안 정답률 ===", SETTLE_THRESHOLD);
    $display("phase0(중심, 시작)  : settle=%0d cycles, 정답률=%0d/%0d(%0d%%)", settle_cycle[0], match_count[0], phase_cycle_count[0], (match_count[0]*100)/phase_cycle_count[0]);
    $display("phase1(모서리로 전환): settle=%0d cycles, 정답률=%0d/%0d(%0d%%)", settle_cycle[1], match_count[1], phase_cycle_count[1], (match_count[1]*100)/phase_cycle_count[1]);
    $display("phase2(중심으로 복귀): settle=%0d cycles, 정답률=%0d/%0d(%0d%%)", settle_cycle[2], match_count[2], phase_cycle_count[2], (match_count[2]*100)/phase_cycle_count[2]);
    $finish;
  end
endmodule
