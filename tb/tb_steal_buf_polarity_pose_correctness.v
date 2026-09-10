`timescale 1ns/1ps

// Directed corner cases plus a source-local FIFO oracle under random traffic.
// The reference v1 instance proves that adding pose storage cannot alter address,
// polarity, arbitration, or overrun behavior.
module tb_steal_buf_polarity_pose_correctness;
  localparam integer POSE_W = 4;
  localparam integer TIMESTAMP_W = 12;
  localparam integer RANDOM_CYCLES = 30000;
  localparam integer SRC = 4; // row 1, column 0: uncontended center-lane source

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;
  reg [POSE_W-1:0] pose_version;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;

  wire [15:0] ov_ref;
  wire vr0; wire [1:0] rr0; wire [3:0] cmr0; wire [3:0] pmr0;
  wire vr1; wire [1:0] rr1; wire [3:0] cmr1; wire [3:0] pmr1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity ref_dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov_ref),
    .valid0(vr0), .row0(rr0), .col_mask0(cmr0), .pol_mask0(pmr0),
    .valid1(vr1), .row1(rr1), .col_mask1(cmr1), .pol_mask1(pmr1));

  wire [15:0] ov;
  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire [(4*POSE_W)-1:0] pt0;
  wire [(4*TIMESTAMP_W)-1:0] tt0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;
  wire [(4*POSE_W)-1:0] pt1;
  wire [(4*TIMESTAMP_W)-1:0] tt1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose #(
    .POSE_W(POSE_W), .TIMESTAMP_W(TIMESTAMP_W)
  ) dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in),
    .pose_version(pose_version), .occurrence_timestamp(occurrence_timestamp),
    .overrun(ov),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .pose_tags0(pt0), .time_tags0(tt0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1),
    .pose_tags1(pt1), .time_tags1(tt1));

  always #5 clk = ~clk;

  integer errors;
  integer addr_mismatch;
  integer overrun_mismatch;
  integer metadata_mismatch;
  integer phantom_count;
  integer duplicate_grant_count;
  integer generated;
  integer accepted;
  integer dropped;
  integer delivered;
  integer checked_events;
  integer cycle_no;
  integer i;
  integer seed;
  integer full_grant_seen;
  integer mixed_pose_seen;
  integer mixed_time_seen;

  reg [1:0] shadow_depth [0:15];
  reg pol_shadow0 [0:15];
  reg pol_shadow1 [0:15];
  reg [POSE_W-1:0] pose_shadow0 [0:15];
  reg [POSE_W-1:0] pose_shadow1 [0:15];
  reg [TIMESTAMP_W-1:0] time_shadow0 [0:15];
  reg [TIMESTAMP_W-1:0] time_shadow1 [0:15];
  reg [15:0] shadow_overrun;
  reg [15:0] ov_sample;
  reg [15:0] ov_ref_sample;
  reg [15:0] granted_sample;

  task automatic check;
    input condition;
    input [511:0] message;
    begin
      if (condition !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL cycle=%0d: %0s", cycle_no, message);
      end
    end
  endtask

  task automatic reset_duts;
    begin
      @(negedge clk);
      rst = 1'b1;
      arrival = 16'd0;
      polarity_in = 16'd0;
      pose_version = 0;
      occurrence_timestamp = 0;
      repeat (2) @(posedge clk);
      #1;
      @(negedge clk);
      rst = 1'b0;
      @(posedge clk);
      #1;
      check(v0 === 1'b0 && v1 === 1'b0, "registered valids clear after reset");
      check(pt0 === 0 && pt1 === 0, "registered pose tags clear after reset");
      check(tt0 === 0 && tt1 === 0, "registered timestamp tags clear after reset");
    end
  endtask

  task automatic compare_registered_outputs;
    begin
      if ({v0, r0, cm0, v1, r1, cm1} !==
          {vr0, rr0, cmr0, vr1, rr1, cmr1}) begin
        addr_mismatch = addr_mismatch + 1;
        errors = errors + 1;
        $display("ADDR_PARITY_FAIL cycle=%0d dut=%b_%0d_%h/%b_%0d_%h ref=%b_%0d_%h/%b_%0d_%h",
          cycle_no, v0, r0, cm0, v1, r1, cm1, vr0, rr0, cmr0, vr1, rr1, cmr1);
      end
      if ({pm0, pm1} !== {pmr0, pmr1}) begin
        metadata_mismatch = metadata_mismatch + 1;
        errors = errors + 1;
        $display("POLARITY_PARITY_FAIL cycle=%0d dut=%h/%h ref=%h/%h",
          cycle_no, pm0, pm1, pmr0, pmr1);
      end
    end
  endtask

  task automatic check_and_pop_lane;
    input lane_valid;
    input [1:0] lane_row;
    input [3:0] lane_cols;
    input [3:0] lane_pols;
    input [(4*POSE_W)-1:0] lane_poses;
    input [(4*TIMESTAMP_W)-1:0] lane_times;
    integer col;
    integer idx;
    reg have_first;
    reg [POSE_W-1:0] first_pose;
    reg [POSE_W-1:0] got_pose;
    reg [TIMESTAMP_W-1:0] first_time;
    reg [TIMESTAMP_W-1:0] got_time;
    begin
      have_first = 1'b0;
      first_pose = 0;
      first_time = 0;
      if (lane_valid && lane_cols == 4'd0) begin
        errors = errors + 1;
        $display("EMPTY_VALID_PACKET cycle=%0d row=%0d", cycle_no, lane_row);
      end
      if (lane_valid) begin
        for (col = 0; col < 4; col = col + 1) begin
          if (lane_cols[col]) begin
            idx = lane_row*4 + col;
            got_pose = lane_poses[(col*POSE_W) +: POSE_W];
            got_time = lane_times[(col*TIMESTAMP_W) +: TIMESTAMP_W];
            if (have_first && got_pose != first_pose)
              mixed_pose_seen = 1;
            if (have_first && got_time != first_time)
              mixed_time_seen = 1;
            if (!have_first) begin
              have_first = 1'b1;
              first_pose = got_pose;
              first_time = got_time;
            end

            if (granted_sample[idx]) begin
              duplicate_grant_count = duplicate_grant_count + 1;
              errors = errors + 1;
              $display("DUPLICATE_GRANT cycle=%0d source=%0d", cycle_no, idx);
            end
            granted_sample[idx] = 1'b1;

            if (shadow_depth[idx] == 2'd0) begin
              phantom_count = phantom_count + 1;
              errors = errors + 1;
              $display("PHANTOM cycle=%0d source=%0d", cycle_no, idx);
            end else begin
              checked_events = checked_events + 1;
              delivered = delivered + 1;
              if (lane_pols[col] !== pol_shadow0[idx]) begin
                metadata_mismatch = metadata_mismatch + 1;
                errors = errors + 1;
                $display("POL_FIFO_FAIL cycle=%0d source=%0d got=%b want=%b",
                  cycle_no, idx, lane_pols[col], pol_shadow0[idx]);
              end
              if (got_pose !== pose_shadow0[idx]) begin
                metadata_mismatch = metadata_mismatch + 1;
                errors = errors + 1;
                $display("POSE_FIFO_FAIL cycle=%0d source=%0d got=%h want=%h",
                  cycle_no, idx, got_pose, pose_shadow0[idx]);
              end
              if (got_time !== time_shadow0[idx]) begin
                metadata_mismatch = metadata_mismatch + 1;
                errors = errors + 1;
                $display("TIME_FIFO_FAIL cycle=%0d source=%0d got=%h want=%h",
                  cycle_no, idx, got_time, time_shadow0[idx]);
              end
              pol_shadow0[idx] = pol_shadow1[idx];
              pose_shadow0[idx] = pose_shadow1[idx];
              time_shadow0[idx] = time_shadow1[idx];
              shadow_depth[idx] = shadow_depth[idx] - 2'd1;
            end
          end
        end
      end
    end
  endtask

  task automatic clear_shadow;
    begin
      for (i = 0; i < 16; i = i + 1) begin
        shadow_depth[i] = 2'd0;
        pol_shadow0[i] = 1'b0;
        pol_shadow1[i] = 1'b0;
        pose_shadow0[i] = 0;
        pose_shadow1[i] = 0;
        time_shadow0[i] = 0;
        time_shadow1[i] = 0;
      end
    end
  endtask

  initial begin
    rst = 1'b1;
    arrival = 16'd0;
    polarity_in = 16'd0;
    pose_version = 0;
    occurrence_timestamp = 0;
    errors = 0;
    addr_mismatch = 0;
    overrun_mismatch = 0;
    metadata_mismatch = 0;
    phantom_count = 0;
    duplicate_grant_count = 0;
    generated = 0;
    accepted = 0;
    dropped = 0;
    delivered = 0;
    checked_events = 0;
    full_grant_seen = 0;
    mixed_pose_seen = 0;
    mixed_time_seen = 0;
    cycle_no = -3;
    seed = 32'h13579bdf;
    clear_shadow();

    // Directed 1: four columns in one row carry four independent tags, including
    // the POSE_W wrap boundary E,F,0,1.
    reset_duts();
    cycle_no = -2;
    for (i = 0; i < 4; i = i + 1) begin
      ref_dut.pending_cnt[4+i] = 2'd1;
      ref_dut.pol_fifo0[4+i] = i[0];
      dut.pending_cnt[4+i] = 2'd1;
      dut.pol_fifo0[4+i] = i[0];
      dut.pose_fifo0[4+i] = 4'he + i;
      dut.time_fifo0[4+i] = 12'hffe + i;
    end
    #1;
    @(posedge clk);
    #1;
    compare_registered_outputs();
    check(v0 === 1'b1 && r0 === 2'd1 && cm0 === 4'hf,
      "one row bitmap contains all four directed events");
    for (i = 0; i < 4; i = i + 1) begin
      check(pt0[(i*POSE_W) +: POSE_W] === ((4'he + i) & 4'hf),
        "column keeps its independent pose tag across wrap");
      check(tt0[(i*TIMESTAMP_W) +: TIMESTAMP_W] === ((12'hffe + i) & 12'hfff),
        "column keeps its independent timestamp across wrap");
    end
    check(pt0[0 +: POSE_W] != pt0[POSE_W +: POSE_W],
      "one bitmap really contains different pose tags");
    if (v0 && cm0[0] && cm0[1] &&
        pt0[0 +: POSE_W] != pt0[POSE_W +: POSE_W])
      mixed_pose_seen = 1;
    if (v0 && cm0[0] && cm0[1] &&
        tt0[0 +: TIMESTAMP_W] != tt0[TIMESTAMP_W +: TIMESTAMP_W])
      mixed_time_seen = 1;

    // Directed 2: v1 full+grant behavior.  The new arrival is reported as overrun
    // and is not smuggled into the slot freed by the simultaneous grant.
    reset_duts();
    cycle_no = -1;
    ref_dut.pending_cnt[SRC] = 2'd2;
    ref_dut.pol_fifo0[SRC] = 1'b0;
    ref_dut.pol_fifo1[SRC] = 1'b1;
    dut.pending_cnt[SRC] = 2'd2;
    dut.pol_fifo0[SRC] = 1'b0;
    dut.pol_fifo1[SRC] = 1'b1;
    dut.pose_fifo0[SRC] = 4'h3;
    dut.pose_fifo1[SRC] = 4'h7;
    dut.time_fifo0[SRC] = 12'h123;
    dut.time_fifo1[SRC] = 12'h456;
    @(negedge clk);
    arrival = 16'd0;
    arrival[SRC] = 1'b1;
    polarity_in = 16'd0;
    pose_version = 4'hd;
    occurrence_timestamp = 12'habc;
    #1;
    check(ov[SRC] === 1'b1 && ov_ref[SRC] === 1'b1,
      "v1 full+grant still reports overrun");
    ov_sample = ov;
    @(posedge clk);
    #1;
    arrival = 16'd0;
    compare_registered_outputs();
    check(v0 && r0 == 2'd1 && cm0[0] && pm0[0] == 1'b0 &&
          pt0[0 +: POSE_W] == 4'h3 &&
          tt0[0 +: TIMESTAMP_W] == 12'h123,
      "full+grant transmits the old front record");
    if (ov_sample[SRC] && v0 && r0 == 2'd1 && cm0[0])
      full_grant_seen = 1;
    @(posedge clk);
    #1;
    compare_registered_outputs();
    check(v0 && r0 == 2'd1 && cm0[0] && pm0[0] == 1'b1 &&
          pt0[0 +: POSE_W] == 4'h7 &&
          tt0[0 +: TIMESTAMP_W] == 12'h456,
      "second grant transmits the old back record");
    @(posedge clk);
    #1;
    compare_registered_outputs();
    check(v0 === 1'b0, "overrun arrival was not admitted as a third record");

    // Directed 3: old depth=1 with grant+arrival must output the old record, then
    // retain the new record in the same front slot (v1 case 2'b11).
    reset_duts();
    cycle_no = 0;
    ref_dut.pending_cnt[SRC] = 2'd1;
    ref_dut.pol_fifo0[SRC] = 1'b0;
    dut.pending_cnt[SRC] = 2'd1;
    dut.pol_fifo0[SRC] = 1'b0;
    dut.pose_fifo0[SRC] = 4'h2;
    dut.time_fifo0[SRC] = 12'h222;
    @(negedge clk);
    arrival = 16'd0;
    arrival[SRC] = 1'b1;
    polarity_in = 16'd0;
    polarity_in[SRC] = 1'b1;
    pose_version = 4'h9;
    occurrence_timestamp = 12'h999;
    #1;
    check(ov[SRC] === 1'b0 && ov_ref[SRC] === 1'b0,
      "depth1 grant+arrival is accepted");
    @(posedge clk);
    #1;
    arrival = 16'd0;
    compare_registered_outputs();
    check(pm0[0] == 1'b0 && pt0[0 +: POSE_W] == 4'h2 &&
          tt0[0 +: TIMESTAMP_W] == 12'h222,
      "simultaneous pop/push outputs the old front record");
    @(posedge clk);
    #1;
    compare_registered_outputs();
    check(pm0[0] == 1'b1 && pt0[0 +: POSE_W] == 4'h9 &&
          tt0[0 +: TIMESTAMP_W] == 12'h999,
      "simultaneous pop/push retains the new record");

    // Random test: independently model every source's depth-2 metadata FIFO.
    reset_duts();
    clear_shadow();
    generated = 0;
    accepted = 0;
    dropped = 0;
    delivered = 0;
    checked_events = 0;

    for (cycle_no = 1; cycle_no <= RANDOM_CYCLES; cycle_no = cycle_no + 1) begin
      @(negedge clk);
      if (cycle_no <= 5000)
        arrival = $random(seed) & $random(seed) & $random(seed);
      else if (cycle_no <= 25000)
        arrival = $random(seed);
      else
        arrival = $random(seed) & $random(seed);
      polarity_in = $random(seed);
      pose_version = cycle_no;
      occurrence_timestamp = cycle_no*17 + 3;
      #1;

      shadow_overrun = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i]) begin
          generated = generated + 1;
          if (shadow_depth[i] == 2'd2) begin
            shadow_overrun[i] = 1'b1;
            dropped = dropped + 1;
          end else begin
            accepted = accepted + 1;
          end
        end
      end
      ov_sample = ov;
      ov_ref_sample = ov_ref;
      if (ov_sample !== ov_ref_sample || ov_sample !== shadow_overrun) begin
        overrun_mismatch = overrun_mismatch + 1;
        errors = errors + 1;
        $display("OVERRUN_FAIL cycle=%0d dut=%h ref=%h oracle=%h",
          cycle_no, ov_sample, ov_ref_sample, shadow_overrun);
      end

      @(posedge clk);
      #1;
      compare_registered_outputs();
      granted_sample = 16'd0;
      check_and_pop_lane(v0, r0, cm0, pm0, pt0, tt0);
      check_and_pop_lane(v1, r1, cm1, pm1, pt1, tt1);

      for (i = 0; i < 16; i = i + 1) begin
        if (shadow_overrun[i] && granted_sample[i])
          full_grant_seen = 1;
        if (arrival[i] && !shadow_overrun[i]) begin
          if (shadow_depth[i] == 2'd0) begin
            pol_shadow0[i] = polarity_in[i];
            pose_shadow0[i] = pose_version;
            time_shadow0[i] = occurrence_timestamp;
          end else if (shadow_depth[i] == 2'd1) begin
            pol_shadow1[i] = polarity_in[i];
            pose_shadow1[i] = pose_version;
            time_shadow1[i] = occurrence_timestamp;
          end else begin
            errors = errors + 1;
            $display("ORACLE_OVERFLOW cycle=%0d source=%0d", cycle_no, i);
          end
          shadow_depth[i] = shadow_depth[i] + 2'd1;
        end
      end
    end

    // Drain long past the finite arbiter bound and prove conservation.
    @(negedge clk);
    arrival = 16'd0;
    polarity_in = 16'd0;
    pose_version = 0;
    occurrence_timestamp = 0;
    for (cycle_no = RANDOM_CYCLES+1; cycle_no <= RANDOM_CYCLES+128; cycle_no = cycle_no + 1) begin
      @(posedge clk);
      #1;
      compare_registered_outputs();
      granted_sample = 16'd0;
      check_and_pop_lane(v0, r0, cm0, pm0, pt0, tt0);
      check_and_pop_lane(v1, r1, cm1, pm1, pt1, tt1);
    end

    for (i = 0; i < 16; i = i + 1)
      check(shadow_depth[i] == 2'd0, "all accepted records drain");
    check(v0 === 1'b0 && v1 === 1'b0, "both output lanes idle after drain");
    check(generated == accepted + dropped, "generated equals accepted plus explicit overrun");
    check(delivered == accepted, "every accepted event is delivered exactly once");
    check(checked_events == delivered, "every delivered event has metadata checked");
    check(full_grant_seen != 0, "full+grant v1 corner was exercised");
    check(mixed_pose_seen != 0, "different pose tags in one bitmap were exercised");
    check(mixed_time_seen != 0, "different timestamp tags in one bitmap were exercised");

    $display("POSE_AER_SUMMARY cycles=%0d generated=%0d accepted=%0d delivered=%0d dropped=%0d checked=%0d",
      RANDOM_CYCLES, generated, accepted, delivered, dropped, checked_events);
    $display("POSE_AER_ERRORS total=%0d addr=%0d overrun=%0d metadata=%0d phantom=%0d duplicate_grant=%0d",
      errors, addr_mismatch, overrun_mismatch, metadata_mismatch, phantom_count, duplicate_grant_count);
    if (errors == 0) begin
      $display("STEAL_BUF_POLARITY_POSE_PASS");
      $display("STEAL_BUF_POLARITY_POSE_TIMESTAMP_PASS");
      $finish;
    end else begin
      $fatal(1, "STEAL_BUF_POLARITY_POSE_FAIL errors=%0d", errors);
    end
  end
endmodule
