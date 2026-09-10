`timescale 1ns/1ps

// End-to-end check for the pose-tagged 4x4 AER -> affine transform pipeline.
// The scoreboard models accepted events by source and never relies on retire-time
// pose inputs.  It also checks the registered AER packet before building the
// independent arithmetic expectation for the following transform cycle.
module tb_aer_tx16_pose_affine2d_e2e;
  localparam POSE_W = 8;
  localparam SENSOR_W = 2;
  localparam RESULT_W = 16;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam FRAC_W = 14;
  localparam TIMESTAMP_W = 32;
  localparam Q = (1 << FRAC_W);
  localparam HALF = (1 << (FRAC_W-1));
  localparam POSE_DEPTH = (1 << POSE_W);

  reg clk = 1'b0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;
  reg [POSE_W-1:0] occurrence_pose_version;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp = {TIMESTAMP_W{1'b0}};
  wire [15:0] overrun;

  reg pose_wr_en;
  reg [POSE_W-1:0] pose_wr_id;
  reg signed [MATRIX_W-1:0] pose_wr_m00;
  reg signed [MATRIX_W-1:0] pose_wr_m01;
  reg signed [MATRIX_W-1:0] pose_wr_m10;
  reg signed [MATRIX_W-1:0] pose_wr_m11;
  reg signed [OFFSET_W-1:0] pose_wr_tx;
  reg signed [OFFSET_W-1:0] pose_wr_ty;

  reg [SENSOR_W-1:0] tile_origin_x;
  reg [SENSOR_W-1:0] tile_origin_y;

  wire [7:0] event_valid_out;
  wire [7:0] mapped_valid_out;
  wire [7:0] pose_found_out;
  wire [7:0] in_range_out;
  wire [7:0] polarity_out;
  wire [8*POSE_W-1:0] pose_version_out_flat;
  wire [8*RESULT_W-1:0] world_x_out_flat;
  wire [8*RESULT_W-1:0] world_y_out_flat;

  aer_tx16_pose_affine2d #(
    .POSE_W(POSE_W), .SENSOR_W(SENSOR_W), .RESULT_W(RESULT_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .TIMESTAMP_W(TIMESTAMP_W),
    .X_MIN(0), .X_MAX(7), .Y_MIN(0), .Y_MAX(7)
  ) dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp), .overrun(overrun),
    .pose_wr_en(pose_wr_en), .pose_wr_id(pose_wr_id),
    .pose_wr_m00(pose_wr_m00), .pose_wr_m01(pose_wr_m01),
    .pose_wr_m10(pose_wr_m10), .pose_wr_m11(pose_wr_m11),
    .pose_wr_tx(pose_wr_tx), .pose_wr_ty(pose_wr_ty),
    .tile_origin_x(tile_origin_x), .tile_origin_y(tile_origin_y),
    .event_valid_out(event_valid_out), .mapped_valid_out(mapped_valid_out),
    .pose_found_out(pose_found_out), .in_range_out(in_range_out),
    .polarity_out(polarity_out),
    .pose_version_out_flat(pose_version_out_flat),
    .world_x_out_flat(world_x_out_flat), .world_y_out_flat(world_y_out_flat)
  );

  always #5 clk = ~clk;

  // Independent source-local two-entry metadata queues.
  integer shadow_depth [0:15];
  reg shadow_pol0 [0:15];
  reg shadow_pol1 [0:15];
  reg [POSE_W-1:0] shadow_pose0 [0:15];
  reg [POSE_W-1:0] shadow_pose1 [0:15];
  integer shadow_id0 [0:15];
  integer shadow_id1 [0:15];

  // Independent pose-table model. Integer storage keeps arithmetic explicit.
  reg model_pose_valid [0:POSE_DEPTH-1];
  integer model_m00 [0:POSE_DEPTH-1];
  integer model_m01 [0:POSE_DEPTH-1];
  integer model_m10 [0:POSE_DEPTH-1];
  integer model_m11 [0:POSE_DEPTH-1];
  integer model_tx [0:POSE_DEPTH-1];
  integer model_ty [0:POSE_DEPTH-1];

  // Expected transform outputs for the next clock edge.
  reg [7:0] exp_valid;
  reg [7:0] exp_found;
  reg [7:0] exp_range;
  reg [7:0] exp_mapped;
  reg exp_pol [0:7];
  reg [POSE_W-1:0] exp_pose [0:7];
  integer exp_x [0:7];
  integer exp_y [0:7];
  integer exp_id [0:7];

  integer cycle_count;
  integer generated_count;
  integer accepted_count;
  integer dropped_count;
  integer retired_count;
  integer mapped_count;
  integer missing_pose_count;
  integer out_of_range_count;
  integer error_count;
  integer next_event_id;
  integer mixed_bitmap_seen;
  reg [255:0] version_seen;

  integer occurrence_case_id;
  integer rotation_case_id;
  integer translation_case_id;
  integer out_of_range_case_id;
  integer missing_pose_case_id;
  integer occurrence_case_seen;
  integer rotation_case_seen;
  integer translation_case_seen;
  integer out_of_range_case_seen;
  integer missing_pose_case_seen;

  function integer round_q14_away_from_zero;
    input integer value;
    integer magnitude;
    begin
      magnitude = (value < 0) ? -value : value;
      round_q14_away_from_zero = (magnitude + HALF) >>> FRAC_W;
      if (value < 0)
        round_q14_away_from_zero = -round_q14_away_from_zero;
    end
  endfunction

  task automatic model_transform;
    input integer pose_id;
    input integer sensor_x;
    input integer sensor_y;
    output integer found;
    output integer in_range;
    output integer mapped;
    output integer world_x;
    output integer world_y;
    integer acc_x;
    integer acc_y;
    begin
      if (!model_pose_valid[pose_id]) begin
        found = 0;
        in_range = 0;
        mapped = 0;
        world_x = 0;
        world_y = 0;
      end else begin
        found = 1;
        acc_x = model_m00[pose_id] * sensor_x
              + model_m01[pose_id] * sensor_y + model_tx[pose_id];
        acc_y = model_m10[pose_id] * sensor_x
              + model_m11[pose_id] * sensor_y + model_ty[pose_id];
        world_x = round_q14_away_from_zero(acc_x);
        world_y = round_q14_away_from_zero(acc_y);
        in_range = (world_x >= 0) && (world_x <= 7)
                && (world_y >= 0) && (world_y <= 7);
        mapped = in_range;
      end
    end
  endtask

  task automatic check_outputs;
    integer slot;
    integer got_x;
    integer got_y;
    integer got_pose;
    begin
      if (event_valid_out !== exp_valid) begin
        $display("EVENT_VALID_MISMATCH cyc=%0d got=%b want=%b",
                 cycle_count, event_valid_out, exp_valid);
        error_count = error_count + 1;
      end
      for (slot = 0; slot < 8; slot = slot + 1) begin
        got_x = $signed(world_x_out_flat[slot*RESULT_W +: RESULT_W]);
        got_y = $signed(world_y_out_flat[slot*RESULT_W +: RESULT_W]);
        got_pose = pose_version_out_flat[slot*POSE_W +: POSE_W];
        if (event_valid_out[slot]) begin
          retired_count = retired_count + 1;
          version_seen[got_pose] = 1'b1;
          if (!pose_found_out[slot])
            missing_pose_count = missing_pose_count + 1;
          else if (!in_range_out[slot])
            out_of_range_count = out_of_range_count + 1;
          else
            mapped_count = mapped_count + 1;
        end
        if (exp_valid[slot]) begin
          if (pose_found_out[slot] !== exp_found[slot]
              || in_range_out[slot] !== exp_range[slot]
              || mapped_valid_out[slot] !== exp_mapped[slot]) begin
            $display("VALIDITY_MISMATCH cyc=%0d slot=%0d found=%b/%b range=%b/%b mapped=%b/%b",
                     cycle_count, slot, pose_found_out[slot], exp_found[slot],
                     in_range_out[slot], exp_range[slot],
                     mapped_valid_out[slot], exp_mapped[slot]);
            error_count = error_count + 1;
          end
          if (polarity_out[slot] !== exp_pol[slot]
              || got_pose != exp_pose[slot]
              || got_x != exp_x[slot] || got_y != exp_y[slot]) begin
            $display("METADATA_MISMATCH cyc=%0d slot=%0d id=%0d pol=%b/%b pose=%0d/%0d xy=(%0d,%0d)/(%0d,%0d)",
                     cycle_count, slot, exp_id[slot],
                     polarity_out[slot], exp_pol[slot], got_pose, exp_pose[slot],
                     got_x, got_y, exp_x[slot], exp_y[slot]);
            error_count = error_count + 1;
          end

          if (exp_id[slot] == occurrence_case_id) begin
            occurrence_case_seen = occurrence_case_seen + 1;
            if (got_pose != 0 || got_x != 3 || got_y != 0)
              error_count = error_count + 1;
          end
          if (exp_id[slot] == rotation_case_id) begin
            rotation_case_seen = rotation_case_seen + 1;
            if (got_pose != 1 || got_x != 3 || got_y != 0)
              error_count = error_count + 1;
          end
          if (exp_id[slot] == translation_case_id) begin
            translation_case_seen = translation_case_seen + 1;
            if (got_pose != 2 || got_x != 4 || got_y != 4)
              error_count = error_count + 1;
          end
          if (exp_id[slot] == out_of_range_case_id) begin
            out_of_range_case_seen = out_of_range_case_seen + 1;
            if (got_pose != 3 || got_x != 10 || got_y != 0
                || pose_found_out[slot] !== 1'b1
                || in_range_out[slot] !== 1'b0)
              error_count = error_count + 1;
          end
          if (exp_id[slot] == missing_pose_case_id) begin
            missing_pose_case_seen = missing_pose_case_seen + 1;
            if (got_pose != 7 || got_x != 0 || got_y != 0
                || pose_found_out[slot] !== 1'b0
                || in_range_out[slot] !== 1'b0)
              error_count = error_count + 1;
          end
        end else if (mapped_valid_out[slot] || pose_found_out[slot]
                     || in_range_out[slot]) begin
          $display("INACTIVE_SLOT_VALIDITY cyc=%0d slot=%0d", cycle_count, slot);
          error_count = error_count + 1;
        end
      end
    end
  endtask

  task automatic clear_expectations;
    integer slot;
    begin
      exp_valid = 8'd0;
      exp_found = 8'd0;
      exp_range = 8'd0;
      exp_mapped = 8'd0;
      for (slot = 0; slot < 8; slot = slot + 1) begin
        exp_pol[slot] = 1'b0;
        exp_pose[slot] = 0;
        exp_x[slot] = 0;
        exp_y[slot] = 0;
        exp_id[slot] = -1;
      end
    end
  endtask

  task automatic capture_aer_lane;
    input integer lane;
    input integer valid_in;
    input [1:0] row_in;
    input [3:0] cols_in;
    input [3:0] pols_in;
    input [(4*POSE_W)-1:0] poses_in;
    integer col;
    integer slot;
    integer source;
    integer found;
    integer in_range;
    integer mapped;
    integer world_x;
    integer world_y;
    integer active_count;
    reg first_tag_valid;
    reg [POSE_W-1:0] first_tag;
    reg tags_differ;
    reg [POSE_W-1:0] hw_tag;
    begin
      active_count = 0;
      first_tag_valid = 1'b0;
      first_tag = 0;
      tags_differ = 1'b0;
      for (col = 0; col < 4; col = col + 1) begin
        slot = lane*4 + col;
        if (valid_in && cols_in[col]) begin
          source = row_in*4 + col;
          hw_tag = poses_in[col*POSE_W +: POSE_W];
          active_count = active_count + 1;
          if (!first_tag_valid) begin
            first_tag_valid = 1'b1;
            first_tag = hw_tag;
          end else if (hw_tag != first_tag) begin
            tags_differ = 1'b1;
          end

          if (shadow_depth[source] == 0) begin
            $display("PHANTOM_AER cyc=%0d lane=%0d source=%0d",
                     cycle_count, lane, source);
            error_count = error_count + 1;
          end else begin
            if (pols_in[col] !== shadow_pol0[source]
                || hw_tag != shadow_pose0[source]) begin
              $display("AER_METADATA_MISMATCH cyc=%0d source=%0d pol=%b/%b pose=%0d/%0d",
                       cycle_count, source, pols_in[col], shadow_pol0[source],
                       hw_tag, shadow_pose0[source]);
              error_count = error_count + 1;
            end

            exp_valid[slot] = 1'b1;
            exp_pol[slot] = shadow_pol0[source];
            exp_pose[slot] = shadow_pose0[source];
            exp_id[slot] = shadow_id0[source];
            model_transform(shadow_pose0[source],
                            tile_origin_x + col, tile_origin_y + row_in,
                            found, in_range, mapped, world_x, world_y);
            exp_found[slot] = found;
            exp_range[slot] = in_range;
            exp_mapped[slot] = mapped;
            exp_x[slot] = world_x;
            exp_y[slot] = world_y;

            shadow_depth[source] = shadow_depth[source] - 1;
            shadow_pol0[source] = shadow_pol1[source];
            shadow_pose0[source] = shadow_pose1[source];
            shadow_id0[source] = shadow_id1[source];
          end
        end
      end
      if (active_count >= 2 && tags_differ)
        mixed_bitmap_seen = mixed_bitmap_seen + 1;
    end
  endtask

  task automatic tick;
    integer source;
    reg [15:0] expected_overrun;
    begin
      #1;
      expected_overrun = 16'd0;
      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source]) begin
          generated_count = generated_count + 1;
          if (shadow_depth[source] == 2) begin
            expected_overrun[source] = 1'b1;
            dropped_count = dropped_count + 1;
          end else begin
            accepted_count = accepted_count + 1;
          end
        end
      end
      if (overrun !== expected_overrun) begin
        $display("OVERRUN_MISMATCH cyc=%0d got=%h want=%h",
                 cycle_count, overrun, expected_overrun);
        error_count = error_count + 1;
      end

      @(posedge clk); #1;
      check_outputs;

      if (pose_wr_en) begin
        model_pose_valid[pose_wr_id] = 1'b1;
        model_m00[pose_wr_id] = $signed(pose_wr_m00);
        model_m01[pose_wr_id] = $signed(pose_wr_m01);
        model_m10[pose_wr_id] = $signed(pose_wr_m10);
        model_m11[pose_wr_id] = $signed(pose_wr_m11);
        model_tx[pose_wr_id] = $signed(pose_wr_tx);
        model_ty[pose_wr_id] = $signed(pose_wr_ty);
      end

      clear_expectations;
      if (dut.aer_valid0 && dut.aer_valid1 && dut.aer_row0 == dut.aer_row1) begin
        $display("AER_LANE_COLLISION cyc=%0d row=%0d", cycle_count, dut.aer_row0);
        error_count = error_count + 1;
      end
      capture_aer_lane(0, dut.aer_valid0, dut.aer_row0, dut.aer_cols0,
                       dut.aer_pols0, dut.aer_poses0);
      capture_aer_lane(1, dut.aer_valid1, dut.aer_row1, dut.aer_cols1,
                       dut.aer_pols1, dut.aer_poses1);

      // Push after popping the grant produced from the pre-edge state. This
      // exactly models v1's simultaneous arrival+grant FIFO semantics.
      for (source = 0; source < 16; source = source + 1) begin
        if (arrival[source] && !expected_overrun[source]) begin
          if (shadow_depth[source] == 0) begin
            shadow_pol0[source] = polarity_in[source];
            shadow_pose0[source] = occurrence_pose_version;
            shadow_id0[source] = next_event_id;
          end else begin
            shadow_pol1[source] = polarity_in[source];
            shadow_pose1[source] = occurrence_pose_version;
            shadow_id1[source] = next_event_id;
          end
          shadow_depth[source] = shadow_depth[source] + 1;
          next_event_id = next_event_id + 1;
        end else if (arrival[source]) begin
          next_event_id = next_event_id + 1;
        end
      end
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic drive_events;
    input [15:0] arrivals;
    input [15:0] polarities;
    input [POSE_W-1:0] pose_version;
    begin
      pose_wr_en = 1'b0;
      arrival = arrivals;
      polarity_in = polarities;
      occurrence_pose_version = pose_version;
      tick;
    end
  endtask

  task automatic load_pose;
    input [POSE_W-1:0] id;
    input integer m00;
    input integer m01;
    input integer m10;
    input integer m11;
    input integer tx;
    input integer ty;
    begin
      arrival = 16'd0;
      polarity_in = 16'd0;
      pose_wr_en = 1'b1;
      pose_wr_id = id;
      pose_wr_m00 = m00;
      pose_wr_m01 = m01;
      pose_wr_m10 = m10;
      pose_wr_m11 = m11;
      pose_wr_tx = tx;
      pose_wr_ty = ty;
      tick;
      pose_wr_en = 1'b0;
    end
  endtask

  integer i;
  integer source;
  initial begin
    rst = 1'b1;
    arrival = 16'd0;
    polarity_in = 16'd0;
    occurrence_pose_version = 0;
    pose_wr_en = 1'b0;
    pose_wr_id = 0;
    pose_wr_m00 = 0; pose_wr_m01 = 0;
    pose_wr_m10 = 0; pose_wr_m11 = 0;
    pose_wr_tx = 0; pose_wr_ty = 0;
    tile_origin_x = 0;
    tile_origin_y = 0;

    cycle_count = 0;
    generated_count = 0;
    accepted_count = 0;
    dropped_count = 0;
    retired_count = 0;
    mapped_count = 0;
    missing_pose_count = 0;
    out_of_range_count = 0;
    error_count = 0;
    next_event_id = 0;
    mixed_bitmap_seen = 0;
    version_seen = 0;
    occurrence_case_id = -1;
    rotation_case_id = -1;
    translation_case_id = -1;
    out_of_range_case_id = -1;
    missing_pose_case_id = -1;
    occurrence_case_seen = 0;
    rotation_case_seen = 0;
    translation_case_seen = 0;
    out_of_range_case_seen = 0;
    missing_pose_case_seen = 0;
    clear_expectations;
    for (source = 0; source < 16; source = source + 1) begin
      shadow_depth[source] = 0;
      shadow_pol0[source] = 0;
      shadow_pol1[source] = 0;
      shadow_pose0[source] = 0;
      shadow_pose1[source] = 0;
      shadow_id0[source] = -1;
      shadow_id1[source] = -1;
    end
    for (i = 0; i < POSE_DEPTH; i = i + 1)
      model_pose_valid[i] = 1'b0;

    repeat (2) begin @(posedge clk); #1; end
    rst = 1'b0;

    // Pose-table programming: identity, exact quarter turn, in-range
    // translation, and a deliberately out-of-range translation.
    load_pose(8'd0, Q, 0, 0, Q, 0, 0);
    load_pose(8'd1, 0, -Q, Q, 0, 3*Q, 0);
    load_pose(8'd2, Q, 0, 0, Q, 2*Q, 3*Q);
    load_pose(8'd3, Q, 0, 0, Q, 10*Q, 0);

    // Build one row bitmap whose two columns have different occurrence tags.
    // Row0 keeps the peripheral lane busy, so the first center contention
    // grants row1 and leaves row2 col0 queued while row2 col1 arrives with a
    // newer pose version.
    drive_events((16'h1 << 0) | (16'h1 << 4) | (16'h1 << 8),
                 16'h0100, 8'd0);
    drive_events((16'h1 << 9), 16'h0200, 8'd1);
    drive_events(16'd0, 16'd0, 8'd2);
    repeat (3) drive_events(16'd0, 16'd0, 8'd3);

    // Capture identity at occurrence, then change the live occurrence-pose
    // input before the event retires. The stored tag must still select pose 0.
    occurrence_case_id = next_event_id;
    drive_events(16'h0008, 16'h0008, 8'd0); // source (x=3,y=0)
    drive_events(16'd0, 16'd0, 8'd2);
    repeat (3) drive_events(16'd0, 16'd0, 8'd2);

    rotation_case_id = next_event_id;
    drive_events(16'h0001, 16'h0001, 8'd1); // (0,0) -> (3,0)
    repeat (4) drive_events(16'd0, 16'd0, 8'd0);

    translation_case_id = next_event_id;
    drive_events(16'h0040, 16'h0040, 8'd2); // (2,1) -> (4,4)
    repeat (4) drive_events(16'd0, 16'd0, 8'd0);

    out_of_range_case_id = next_event_id;
    drive_events(16'h0001, 16'h0000, 8'd3); // (0,0) -> (10,0)
    repeat (4) drive_events(16'd0, 16'd0, 8'd0);

    missing_pose_case_id = next_event_id;
    drive_events(16'h8000, 16'h8000, 8'd7); // pose 7 was never loaded
    repeat (4) drive_events(16'd0, 16'd0, 8'd0);

    // Both bitmap lanes, every row, and all columns in one burst.
    drive_events(16'hffff, 16'ha55a, 8'd2);
    repeat (6) drive_events(16'd0, 16'd0, 8'd0);

    // Row0 holds the peripheral lane, forcing rows1/2 to share the center lane.
    // Sustained arrivals then fill both source-local FIFOs and prove v1 overrun
    // accounting while pose and polarity metadata continue to vary.
    for (i = 0; i < 20; i = i + 1)
      drive_events((16'h1 << 0) | (16'h1 << 4) | (16'h1 << 8),
                   (i[0] ? (16'h1 << 4) : (16'h1 << 8)), i[1:0]);

    // Bounded drain, then two extra empty pipeline cycles.
    repeat (100) drive_events(16'd0, 16'd0, 8'd0);

    for (source = 0; source < 16; source = source + 1) begin
      if (shadow_depth[source] != 0) begin
        $display("DRAIN_INCOMPLETE source=%0d depth=%0d",
                 source, shadow_depth[source]);
        error_count = error_count + 1;
      end
    end
    if (exp_valid != 0 || event_valid_out != 0
        || dut.aer_valid0 || dut.aer_valid1) begin
      $display("PIPELINE_NOT_EMPTY exp=%b out=%b aer=%b%b",
               exp_valid, event_valid_out, dut.aer_valid1, dut.aer_valid0);
      error_count = error_count + 1;
    end
    if (generated_count != accepted_count + dropped_count) begin
      $display("INPUT_CONSERVATION_FAIL generated=%0d accepted=%0d dropped=%0d",
               generated_count, accepted_count, dropped_count);
      error_count = error_count + 1;
    end
    if (accepted_count != retired_count) begin
      $display("DRAIN_CONSERVATION_FAIL accepted=%0d retired=%0d",
               accepted_count, retired_count);
      error_count = error_count + 1;
    end
    if (retired_count != mapped_count + missing_pose_count + out_of_range_count) begin
      $display("OUTPUT_ACCOUNTING_FAIL retired=%0d mapped=%0d missing=%0d oor=%0d",
               retired_count, mapped_count, missing_pose_count, out_of_range_count);
      error_count = error_count + 1;
    end
    if (dropped_count == 0 || missing_pose_count == 0
        || out_of_range_count == 0 || mixed_bitmap_seen == 0) begin
      $display("COVERAGE_FAIL dropped=%0d missing=%0d oor=%0d mixed=%0d",
               dropped_count, missing_pose_count,
               out_of_range_count, mixed_bitmap_seen);
      error_count = error_count + 1;
    end
    if (!version_seen[0] || !version_seen[1] || !version_seen[2]
        || !version_seen[3] || !version_seen[7]) begin
      $display("POSE_VERSION_COVERAGE_FAIL seen=%h", version_seen);
      error_count = error_count + 1;
    end
    if (occurrence_case_seen != 1 || rotation_case_seen != 1
        || translation_case_seen != 1 || out_of_range_case_seen != 1
        || missing_pose_case_seen != 1) begin
      $display("DIRECTED_CASE_COUNT_FAIL occurrence=%0d rotation=%0d translation=%0d oor=%0d missing=%0d",
               occurrence_case_seen, rotation_case_seen, translation_case_seen,
               out_of_range_case_seen, missing_pose_case_seen);
      error_count = error_count + 1;
    end

    $display("SUMMARY generated=%0d accepted=%0d dropped=%0d retired=%0d mapped=%0d missing_pose=%0d out_of_range=%0d mixed_bitmap=%0d",
             generated_count, accepted_count, dropped_count, retired_count,
             mapped_count, missing_pose_count, out_of_range_count,
             mixed_bitmap_seen);
    if (error_count == 0)
      $display("AER_TX16_POSE_AFFINE2D_E2E_PASS");
    else
      $display("AER_TX16_POSE_AFFINE2D_E2E_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
