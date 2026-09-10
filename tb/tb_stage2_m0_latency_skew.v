// Stage-2 M0 baseline for the final Stage-1 AER.
// An external event-ID oracle checks accepted-event conservation, no phantom
// or duplicate retirement, source FIFO order, polarity, latency percentiles,
// and retire skew among different sources accepted in the same cycle.
`timescale 1ns/1ps
module tb_stage2_m0_latency_skew;
  parameter STIM_CYCLES = 4096;
  parameter DRAIN_CYCLES = 64;
  parameter ARRIVAL_PCT = 18;
  parameter BURST_PERIOD = 64;
  parameter BURST_CYCLES = 4;
  localparam MAX_EVENTS = STIM_CYCLES * 16;
  localparam HIST_MAX = 255;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;
  wire [15:0] overrun;
  wire valid0;
  wire [1:0] row0;
  wire [3:0] col_mask0;
  wire [3:0] pol_mask0;
  wire valid1;
  wire [1:0] row1;
  wire [3:0] col_mask1;
  wire [3:0] pol_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity dut (
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .pol_mask0(pol_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .pol_mask1(pol_mask1)
  );

  always #5 clk = ~clk;

  integer fifo_depth [0:15];
  integer fifo_id0 [0:15];
  integer fifo_id1 [0:15];
  integer fifo_cycle0 [0:15];
  integer fifo_cycle1 [0:15];
  integer fifo_group0 [0:15];
  integer fifo_group1 [0:15];
  reg fifo_pol0 [0:15];
  reg fifo_pol1 [0:15];
  integer last_retired_id [0:15];

  integer arrival_id [0:15];
  integer retired_seen [0:MAX_EVENTS-1];
  integer latency_hist [0:HIST_MAX];
  integer skew_hist [0:HIST_MAX];
  integer group_accepted [0:STIM_CYCLES-1];
  integer group_retired [0:STIM_CYCLES-1];
  integer group_first_retire [0:STIM_CYCLES-1];
  integer group_last_retire [0:STIM_CYCLES-1];

  integer generated;
  integer accepted;
  integer dropped;
  integer retired;
  integer phantom_count;
  integer duplicate_count;
  integer order_count;
  integer polarity_count;
  integer overrun_mismatch_count;
  integer source_collision_count;
  integer latency_hist_overflow;
  integer skew_hist_overflow;
  integer max_latency;
  integer max_skew;
  integer error_count;
  integer next_event_id;
  integer rng_seed;
  integer cyc;
  integer i;
  integer c;
  integer draw;
  integer drain;
  integer pending_total;
  integer group_count;
  integer group_skew;
  integer cumulative;
  integer target50;
  integer target99;
  integer latency_p50;
  integer latency_p99;
  integer skew_p50;
  integer skew_p99;
  reg [15:0] overrun_sample;
  reg [15:0] retired_sources_this_cycle;

  task automatic retire_lane;
    input integer lane_valid;
    input [1:0] lane_row;
    input [3:0] lane_cols;
    input [3:0] lane_pols;
    integer source;
    integer event_id;
    integer occurrence_cycle;
    integer group_id;
    integer latency;
    begin
      if (lane_valid) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (lane_cols[c]) begin
            source = lane_row * 4 + c;
            if (retired_sources_this_cycle[source]) begin
              source_collision_count = source_collision_count + 1;
              error_count = error_count + 1;
              $display("SOURCE_RETIRED_TWICE cycle=%0d source=%0d", cyc, source);
            end
            retired_sources_this_cycle[source] = 1'b1;

            if (fifo_depth[source] == 0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM cycle=%0d source=%0d", cyc, source);
            end else begin
              event_id = fifo_id0[source];
              occurrence_cycle = fifo_cycle0[source];
              group_id = fifo_group0[source];

              if (lane_pols[c] !== fifo_pol0[source]) begin
                polarity_count = polarity_count + 1;
                error_count = error_count + 1;
                $display("POLARITY_MISMATCH cycle=%0d source=%0d id=%0d", cyc, source, event_id);
              end
              if (event_id <= last_retired_id[source]) begin
                order_count = order_count + 1;
                error_count = error_count + 1;
                $display("ORDER_VIOLATION cycle=%0d source=%0d id=%0d last=%0d",
                         cyc, source, event_id, last_retired_id[source]);
              end
              last_retired_id[source] = event_id;

              if (retired_seen[event_id] != 0) begin
                duplicate_count = duplicate_count + 1;
                error_count = error_count + 1;
                $display("DUPLICATE cycle=%0d source=%0d id=%0d", cyc, source, event_id);
              end
              retired_seen[event_id] = 1;

              latency = cyc - occurrence_cycle;
              if (latency > max_latency)
                max_latency = latency;
              if (latency >= 0 && latency <= HIST_MAX)
                latency_hist[latency] = latency_hist[latency] + 1;
              else begin
                latency_hist_overflow = latency_hist_overflow + 1;
                error_count = error_count + 1;
                $display("LATENCY_OUT_OF_RANGE cycle=%0d source=%0d latency=%0d", cyc, source, latency);
              end

              group_retired[group_id] = group_retired[group_id] + 1;
              if (group_retired[group_id] == 1)
                group_first_retire[group_id] = cyc;
              group_last_retire[group_id] = cyc;

              fifo_id0[source] = fifo_id1[source];
              fifo_cycle0[source] = fifo_cycle1[source];
              fifo_group0[source] = fifo_group1[source];
              fifo_pol0[source] = fifo_pol1[source];
              fifo_depth[source] = fifo_depth[source] - 1;
              retired = retired + 1;
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 16'd0;
    polarity_in = 16'd0;
    generated = 0;
    accepted = 0;
    dropped = 0;
    retired = 0;
    phantom_count = 0;
    duplicate_count = 0;
    order_count = 0;
    polarity_count = 0;
    overrun_mismatch_count = 0;
    source_collision_count = 0;
    latency_hist_overflow = 0;
    skew_hist_overflow = 0;
    max_latency = 0;
    max_skew = 0;
    error_count = 0;
    next_event_id = 0;
    rng_seed = 32'h51a6e2;

    for (i = 0; i < 16; i = i + 1) begin
      fifo_depth[i] = 0;
      fifo_id0[i] = -1;
      fifo_id1[i] = -1;
      fifo_cycle0[i] = -1;
      fifo_cycle1[i] = -1;
      fifo_group0[i] = -1;
      fifo_group1[i] = -1;
      fifo_pol0[i] = 1'b0;
      fifo_pol1[i] = 1'b0;
      last_retired_id[i] = -1;
      arrival_id[i] = -1;
    end
    for (i = 0; i < MAX_EVENTS; i = i + 1)
      retired_seen[i] = 0;
    for (i = 0; i <= HIST_MAX; i = i + 1) begin
      latency_hist[i] = 0;
      skew_hist[i] = 0;
    end
    for (i = 0; i < STIM_CYCLES; i = i + 1) begin
      group_accepted[i] = 0;
      group_retired[i] = 0;
      group_first_retire[i] = -1;
      group_last_retire[i] = -1;
    end

    repeat (2) begin
      @(posedge clk);
      #1;
    end
    rst = 1'b0;

    for (cyc = 0; cyc < STIM_CYCLES; cyc = cyc + 1) begin
      if ((cyc % BURST_PERIOD) < BURST_CYCLES) begin
        arrival = 16'hffff;
      end else begin
        arrival = 16'd0;
        for (i = 0; i < 16; i = i + 1) begin
          draw = (($random(rng_seed) % 100) + 100) % 100;
          if (draw < ARRIVAL_PCT)
            arrival[i] = 1'b1;
        end
      end
      for (i = 0; i < 16; i = i + 1)
        polarity_in[i] = (cyc + i) & 1;

      #1;
      overrun_sample = overrun;
      for (i = 0; i < 16; i = i + 1) begin
        arrival_id[i] = -1;
        if (overrun_sample[i] !== (arrival[i] && (fifo_depth[i] == 2))) begin
          overrun_mismatch_count = overrun_mismatch_count + 1;
          error_count = error_count + 1;
          $display("OVERRUN_MISMATCH cycle=%0d source=%0d got=%b depth=%0d arrival=%b",
                   cyc, i, overrun_sample[i], fifo_depth[i], arrival[i]);
        end
        if (arrival[i]) begin
          arrival_id[i] = next_event_id;
          next_event_id = next_event_id + 1;
          generated = generated + 1;
          if (overrun_sample[i])
            dropped = dropped + 1;
          else begin
            accepted = accepted + 1;
            group_accepted[cyc] = group_accepted[cyc] + 1;
          end
        end
      end

      @(posedge clk);
      #1;
      retired_sources_this_cycle = 16'd0;
      retire_lane(valid0, row0, col_mask0, pol_mask0);
      retire_lane(valid1, row1, col_mask1, pol_mask1);

      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && !overrun_sample[i]) begin
          if (fifo_depth[i] == 0) begin
            fifo_id0[i] = arrival_id[i];
            fifo_cycle0[i] = cyc;
            fifo_group0[i] = cyc;
            fifo_pol0[i] = polarity_in[i];
          end else if (fifo_depth[i] == 1) begin
            fifo_id1[i] = arrival_id[i];
            fifo_cycle1[i] = cyc;
            fifo_group1[i] = cyc;
            fifo_pol1[i] = polarity_in[i];
          end else begin
            error_count = error_count + 1;
            $display("ORACLE_OVERFLOW cycle=%0d source=%0d depth=%0d", cyc, i, fifo_depth[i]);
          end
          fifo_depth[i] = fifo_depth[i] + 1;
        end
      end
    end

    arrival = 16'd0;
    polarity_in = 16'd0;
    for (drain = 0; drain < DRAIN_CYCLES; drain = drain + 1) begin
      cyc = STIM_CYCLES + drain;
      @(posedge clk);
      #1;
      retired_sources_this_cycle = 16'd0;
      retire_lane(valid0, row0, col_mask0, pol_mask0);
      retire_lane(valid1, row1, col_mask1, pol_mask1);
    end

    pending_total = 0;
    for (i = 0; i < 16; i = i + 1)
      pending_total = pending_total + fifo_depth[i];
    if (generated !== accepted + dropped) begin
      error_count = error_count + 1;
      $display("GENERATED_ACCOUNTING_FAIL generated=%0d accepted=%0d dropped=%0d",
               generated, accepted, dropped);
    end
    if (accepted !== retired + pending_total) begin
      error_count = error_count + 1;
      $display("CONSERVATION_FAIL accepted=%0d retired=%0d pending=%0d",
               accepted, retired, pending_total);
    end
    if (pending_total != 0) begin
      error_count = error_count + 1;
      $display("DRAIN_INCOMPLETE pending=%0d", pending_total);
    end

    group_count = 0;
    for (i = 0; i < STIM_CYCLES; i = i + 1) begin
      if (group_retired[i] !== group_accepted[i]) begin
        error_count = error_count + 1;
        $display("GROUP_CONSERVATION_FAIL group=%0d accepted=%0d retired=%0d",
                 i, group_accepted[i], group_retired[i]);
      end
      if (group_accepted[i] >= 2 && group_retired[i] == group_accepted[i]) begin
        group_skew = group_last_retire[i] - group_first_retire[i];
        group_count = group_count + 1;
        if (group_skew > max_skew)
          max_skew = group_skew;
        if (group_skew >= 0 && group_skew <= HIST_MAX)
          skew_hist[group_skew] = skew_hist[group_skew] + 1;
        else begin
          skew_hist_overflow = skew_hist_overflow + 1;
          error_count = error_count + 1;
        end
      end
    end

    latency_p50 = -1;
    latency_p99 = -1;
    cumulative = 0;
    target50 = (retired + 1) / 2;
    target99 = (retired * 99 + 99) / 100;
    for (i = 0; i <= HIST_MAX; i = i + 1) begin
      cumulative = cumulative + latency_hist[i];
      if (latency_p50 < 0 && cumulative >= target50)
        latency_p50 = i;
      if (latency_p99 < 0 && cumulative >= target99)
        latency_p99 = i;
    end

    skew_p50 = -1;
    skew_p99 = -1;
    cumulative = 0;
    target50 = (group_count + 1) / 2;
    target99 = (group_count * 99 + 99) / 100;
    for (i = 0; i <= HIST_MAX; i = i + 1) begin
      cumulative = cumulative + skew_hist[i];
      if (skew_p50 < 0 && cumulative >= target50)
        skew_p50 = i;
      if (skew_p99 < 0 && cumulative >= target99)
        skew_p99 = i;
    end

    $display("M0_COUNTS generated=%0d accepted=%0d retired=%0d dropped_overrun=%0d pending=%0d",
             generated, accepted, retired, dropped, pending_total);
    $display("M0_LATENCY count=%0d p50=%0d p99=%0d max=%0d cycles",
             retired, latency_p50, latency_p99, max_latency);
    $display("M0_CROSS_SOURCE_SKEW groups=%0d p50=%0d p99=%0d max=%0d cycles",
             group_count, skew_p50, skew_p99, max_skew);
    $display("M0_ERRORS phantom=%0d duplicate=%0d order=%0d polarity=%0d overrun=%0d source_collision=%0d lat_hist_overflow=%0d skew_hist_overflow=%0d",
             phantom_count, duplicate_count, order_count, polarity_count,
             overrun_mismatch_count, source_collision_count,
             latency_hist_overflow, skew_hist_overflow);
    if (error_count == 0) begin
      $display("STAGE2_M0_PASS");
      $finish;
    end else begin
      $fatal(1, "STAGE2_M0_FAIL errors=%0d", error_count);
    end
  end
endmodule
