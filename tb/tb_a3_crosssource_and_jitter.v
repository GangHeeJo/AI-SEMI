// §67(cross-source spread)와 §68(same-source jitter)를 준영의 A3 RTL에 그대로 적용.
// A3는 우리 cluster2와 달리 레인이 독립적이지 않고(g0,g1이 하나의 공유 순위에서
// 순차로 뽑힘, col_mask 같은 행단위 묶음도 없음) 구조적 보장이 있는지 실측으로 확인.
`timescale 1ns/1ps
module tb_a3_crosssource_and_jitter;
  parameter MAX_BATCHES = 64;

  reg clk = 0;
  reg rst;
  reg [15:0] source_pending;
  wire [1:0] grant_count;
  wire [3:0] lane0_addr, lane1_addr;
  reg bundle_ready;

  a3_exact_scalar_prefix_k2 dut(
    .clk(clk), .rst(rst),
    .source_pending(source_pending),
    .grant_count(grant_count),
    .lane0_addr(lane0_addr),
    .lane1_addr(lane1_addr),
    .bundle_ready(bundle_ready));

  always #5 clk = ~clk;

  integer cyc, i;
  reg [15:0] pending;
  integer error_count;

  // -- batch(동시발화) 추적: §67과 동일한 sticky "마지막 유효 grant" 방식이 아니라
  //    "이번 배치에 속한 소스가 실제로 배달된 사이클"을 직접 기록.
  integer batch_active [0:MAX_BATCHES-1];
  integer batch_member [0:MAX_BATCHES-1][0:15];
  integer batch_ksize [0:MAX_BATCHES-1];
  integer batch_recorded [0:MAX_BATCHES-1];
  integer batch_min_dep [0:MAX_BATCHES-1];
  integer batch_max_dep [0:MAX_BATCHES-1];
  integer new_batch_members [0:15];
  integer scen_spread_sum, scen_spread_count, scen_max_spread, scen_batches_done;

  // -- jitter(같은 소스 연속 latency 변동폭) --
  integer arrival_cyc [0:15];
  integer last_lat [0:15]; integer have_last [0:15];
  integer jit_sum, jit_cnt, max_lat;

  task automatic batch_reset_all;
    integer b; begin for (b=0;b<MAX_BATCHES;b=b+1) batch_active[b]=0; end
  endtask

  task automatic batch_start;
    input integer ksize;
    integer b, slot, s;
    begin
      slot = -1;
      for (b=0;b<MAX_BATCHES;b=b+1) if (!batch_active[b] && slot<0) slot=b;
      if (slot>=0) begin
        batch_active[slot]=1; batch_ksize[slot]=ksize; batch_recorded[slot]=0;
        batch_min_dep[slot]=32'h7fffffff; batch_max_dep[slot]=-1;
        for (s=0;s<16;s=s+1) batch_member[slot][s]=new_batch_members[s];
      end
    end
  endtask

  task automatic on_deliver;
    input integer addr;
    integer b, lat;
    begin
      // jitter
      if (arrival_cyc[addr] >= 0) begin
        lat = cyc - arrival_cyc[addr];
        if (lat > max_lat) max_lat = lat;
        if (have_last[addr]) begin
          jit_sum = jit_sum + ((lat>last_lat[addr])?(lat-last_lat[addr]):(last_lat[addr]-lat));
          jit_cnt = jit_cnt + 1;
        end
        last_lat[addr] = lat; have_last[addr] = 1;
      end
      arrival_cyc[addr] = -1;
      // batch spread
      for (b=0;b<MAX_BATCHES;b=b+1) begin
        if (batch_active[b] && batch_member[b][addr]) begin
          batch_recorded[b]=batch_recorded[b]+1;
          if (cyc<batch_min_dep[b]) batch_min_dep[b]=cyc;
          if (cyc>batch_max_dep[b]) batch_max_dep[b]=cyc;
          if (batch_recorded[b]==batch_ksize[b]) begin
            scen_spread_sum = scen_spread_sum + (batch_max_dep[b]-batch_min_dep[b]);
            scen_spread_count = scen_spread_count + 1;
            if ((batch_max_dep[b]-batch_min_dep[b])>scen_max_spread)
              scen_max_spread = batch_max_dep[b]-batch_min_dep[b];
            scen_batches_done = scen_batches_done + 1;
            batch_active[b]=0;
          end
        end
      end
    end
  endtask

  task automatic step;
    begin
      source_pending = pending;
      @(posedge clk); #1;
      if (grant_count >= 2'd1) begin
        if (!pending[lane0_addr]) error_count = error_count + 1;
        pending[lane0_addr] = 1'b0;
        on_deliver(lane0_addr);
      end
      if (grant_count == 2'd2) begin
        if (!pending[lane1_addr]) error_count = error_count + 1;
        pending[lane1_addr] = 1'b0;
        on_deliver(lane1_addr);
      end
      cyc = cyc + 1;
    end
  endtask

  task automatic run_until_drained;
    integer guard;
    begin
      guard = 0;
      while ((pending != 16'd0) && guard < 100000) begin
        step; guard = guard + 1;
      end
    end
  endtask

  task automatic clear_members;
    integer s; begin for (s=0;s<16;s=s+1) new_batch_members[s]=0; end
  endtask

  task automatic inject_and_batch;
    integer s, ksize;
    begin
      ksize=0;
      for (s=0;s<16;s=s+1) if (new_batch_members[s]) begin
        pending[s]=1'b1; arrival_cyc[s]=cyc; ksize=ksize+1;
      end
      batch_start(ksize);
    end
  endtask

  task automatic report_scenario;
    input [39*8:1] label;
    begin
      if (scen_spread_count>0)
        $display("SCEN=%0s batches=%0d avg_spread=%0d.%0d max_spread=%0d",
          label, scen_batches_done, scen_spread_sum/scen_spread_count,
          (scen_spread_sum*10/scen_spread_count)%10, scen_max_spread);
      else $display("SCEN=%0s batches=0", label);
    end
  endtask

  integer draw, rng_seed;
  initial begin
    rst=1; pending=16'd0; bundle_ready=1'b1; cyc=0; error_count=0;
    rng_seed = 3;
    for (i=0;i<16;i=i+1) begin arrival_cyc[i]=-1; have_last[i]=0; end
    source_pending = 16'd0;
    @(posedge clk); #1; rst=0;
    batch_reset_all;

    // A: 같은 행(row1) 4열 동시발화
    scen_spread_sum=0; scen_spread_count=0; scen_max_spread=0; scen_batches_done=0;
    for (i=0;i<5;i=i+1) begin
      clear_members;
      new_batch_members[4]=1; new_batch_members[5]=1;
      new_batch_members[6]=1; new_batch_members[7]=1;
      inject_and_batch;
      run_until_drained;
    end
    report_scenario("A_same_row_4col");

    // C: 다른 그룹(중심1개+주변1개) 동시발화
    scen_spread_sum=0; scen_spread_count=0; scen_max_spread=0; scen_batches_done=0;
    for (i=0;i<20;i=i+1) begin
      clear_members;
      new_batch_members[4]=1; new_batch_members[0]=1;
      inject_and_batch;
      run_until_drained;
    end
    report_scenario("C_cross_group");

    // jitter: 소스당 확률적 배경부하 (load_pct 스윕)
    jit_sum=0; jit_cnt=0; max_lat=0;
    for (i=0;i<16;i=i+1) have_last[i]=0;
    begin : jitter_phase
      integer jcount;
      for (jcount=0; jcount<3000; jcount=jcount+1) begin
        for (i=0;i<16;i=i+1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw<15 && !pending[i]) begin
            pending[i]=1'b1; arrival_cyc[i]=cyc;
          end
        end
        step;
      end
    end
    $display("JITTER load=15%% avg_jit=%0d.%0d max_lat=%0d jit_cnt=%0d",
      (jit_cnt>0)?jit_sum/jit_cnt:0, (jit_cnt>0)?((jit_sum*10/jit_cnt)%10):0, max_lat, jit_cnt);

    if (error_count==0) $display("A3_CROSSSOURCE_JITTER_PASS");
    else $display("A3_CROSSSOURCE_JITTER_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
