// 8x8 v2로 "움직이는 물체 실시간 추적" 검증. 중심4행(2,3,4,5)→주변4행(0,1,6,7)→중심 복귀.
`ifndef PHASE_LEN_VAL
`define PHASE_LEN_VAL 1500
`endif
module tb_moving_hotspot64_v2;
  parameter QDEPTH = 64;
  parameter BG_PCT = 2;
  parameter HOT_PCT = 20;
  parameter PHASE_LEN = `PHASE_LEN_VAL;
  parameter TOTAL_CYCLES = PHASE_LEN * 3;

  reg clk = 0;
  reg rst;
  reg [63:0] req;
  reg [63:0] new_event;
  wire       valid, addr_type;
  wire [2:0] addr;
  wire       event_valid;
  wire [2:0] event_row, event_col;

  aer_tx64_adaptive_v2 tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));
  aer_rx64 rx(.clk(clk), .rst(rst), .valid(valid), .addr_type(addr_type), .addr(addr),
              .event_valid(event_valid), .event_row(event_row), .event_col(event_col));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer queue [0:63][0:QDEPTH-1];
  integer qhead [0:63];
  integer qcount [0:63];
  integer cyc, i, idx, latency, phase;

  function integer current_phase(input integer c);
    if ((c/PHASE_LEN) % 2 == 0) current_phase = 0; // 중심
    else current_phase = 1; // 주변
  endfunction

  function is_hotspot(input integer idx_, input integer ph);
    integer r;
    begin
      r = idx_ / 8;
      if (ph == 0) is_hotspot = (r==2||r==3||r==4||r==5);
      else is_hotspot = (r==0||r==1||r==6||r==7);
    end
  endfunction

  function [7:0] expected_hot_mask(input integer ph);
    if (ph == 0) expected_hot_mask = 8'b00111100;
    else expected_hot_mask = 8'b11000011;
  endfunction

  integer transition_cycle [0:2];
  integer settle_cycle [0:2];
  integer match_streak [0:2];
  integer match_count [0:2];
  integer phase_cycle_count [0:2];
  localparam SETTLE_THRESHOLD = 20;

  initial begin
    rst = 1; req = 64'd0; new_event = 64'd0;
    for (i=0;i<64;i=i+1) begin qhead[i]=0; qcount[i]=0; end
    transition_cycle[0]=0; transition_cycle[1]=PHASE_LEN; transition_cycle[2]=PHASE_LEN*2;
    settle_cycle[0]=-1; settle_cycle[1]=-1; settle_cycle[2]=-1;
    match_streak[0]=0; match_streak[1]=0; match_streak[2]=0;
    match_count[0]=0; match_count[1]=0; match_count[2]=0;
    phase_cycle_count[0]=0; phase_cycle_count[1]=0; phase_cycle_count[2]=0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < TOTAL_CYCLES; cyc = cyc + 1) begin
      phase = current_phase(cyc);
      new_event = 64'd0;
      for (i = 0; i < 64; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i,phase) ? HOT_PCT : BG_PCT)) begin
          new_event[i] = 1'b1;
          if (qcount[i] < QDEPTH) begin
            queue[i][(qhead[i]+qcount[i])%QDEPTH] = cyc;
            qcount[i] = qcount[i] + 1;
          end
        end
      end
      for (i = 0; i < 64; i = i + 1) req[i] = (qcount[i] > 0);

      @(posedge clk); #1;

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
        idx = event_row*8+event_col;
        if (qcount[idx] > 0) begin
          latency = cyc - queue[idx][qhead[idx]];
          qhead[idx] = (qhead[idx]+1)%QDEPTH;
          qcount[idx] = qcount[idx]-1;
        end
      end
    end

    $display("=== [64/v2] settle + phase별 정답률 ===");
    $display("phase0(중심,시작)   : settle=%0d, 정답률=%0d/%0d(%0d%%)", settle_cycle[0], match_count[0], phase_cycle_count[0], (match_count[0]*100)/phase_cycle_count[0]);
    $display("phase1(주변으로전환): settle=%0d, 정답률=%0d/%0d(%0d%%)", settle_cycle[1], match_count[1], phase_cycle_count[1], (match_count[1]*100)/phase_cycle_count[1]);
    $display("phase2(중심으로복귀): settle=%0d, 정답률=%0d/%0d(%0d%%)", settle_cycle[2], match_count[2], phase_cycle_count[2], (match_count[2]*100)/phase_cycle_count[2]);
    $finish;
  end
endmodule
