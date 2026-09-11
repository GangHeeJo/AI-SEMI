`timescale 1ns/1ps

module tb_aer_tx256_region_shared_affine;
  localparam integer SENSOR_W = 8;
  localparam integer REGION_COLS = 30;
  localparam integer REGION_ROWS = 23;
  localparam integer REGION_COUNT = REGION_COLS * REGION_ROWS;
  localparam integer REGION_ID_W = 10;
  localparam integer RESULT_W = 16;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer FRAC_W = 4;
  localparam integer TIMESTAMP_W = 35;
  localparam integer REGION_FIFO_DEPTH = 8;
  localparam integer SHARED_FIFO_DEPTH = 8;
  localparam integer GUARD_COUNT_W = 10;
  localparam integer Q_ONE = 1 << FRAC_W;
  localparam integer BASE_X = 32;
  localparam integer BASE_Y = 40;
  localparam integer MAX_EXPECTED = 128;
  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;
  localparam [1:0] CFG_ABORT = 2'd3;

  reg clk;
  reg rst;
  reg [255:0] arrival;
  reg [255:0] polarity_in;
  reg [TIMESTAMP_W-1:0] occurrence_timestamp;
  reg [SENSOR_W-1:0] base_sensor_origin_x;
  reg [SENSOR_W-1:0] base_sensor_origin_y;
  wire [255:0] arrival_blocked;
  wire sensor_admission_enabled;
  wire [255:0] aer_overrun;
  wire [127:0] leaf_fifo_overflow;
  wire shared_fifo_overflow;

  reg cfg_valid;
  wire cfg_ready;
  reg [1:0] cfg_op;
  reg [4:0] cfg_region_x;
  reg [4:0] cfg_region_y;
  reg cfg_pose_version;
  reg signed [MATRIX_W-1:0] cfg_m00;
  reg signed [MATRIX_W-1:0] cfg_m01;
  reg signed [MATRIX_W-1:0] cfg_m10;
  reg signed [MATRIX_W-1:0] cfg_m11;
  reg signed [OFFSET_W-1:0] cfg_tx;
  reg signed [OFFSET_W-1:0] cfg_ty;
  wire active_pose_valid;
  wire active_pose_version;
  wire cfg_busy;
  wire cfg_awaiting_publish;
  wire cfg_publish_pulse;
  wire cfg_protocol_error;

  wire world_valid;
  reg world_ready;
  wire mapped_valid;
  wire pose_found;
  wire in_range;
  wire [REGION_ID_W-1:0] region_id_out;
  wire [SENSOR_W-1:0] sensor_x_out;
  wire [SENSOR_W-1:0] sensor_y_out;
  wire polarity_out;
  wire pose_version_out;
  wire [TIMESTAMP_W-1:0] occurrence_timestamp_out;
  wire signed [RESULT_W-1:0] world_x_out;
  wire signed [RESULT_W-1:0] world_y_out;
  wire [GUARD_COUNT_W-1:0] pose_outstanding0;
  wire [GUARD_COUNT_W-1:0] pose_outstanding1;
  wire [1:0] pose_overwrite_ready;
  wire pose_accounting_error;

  aer_tx256_region_shared_affine #(
    .SENSOR_COLS(240), .SENSOR_ROWS(180), .SENSOR_W(SENSOR_W),
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(5), .REGION_Y_W(5), .REGION_ID_W(REGION_ID_W),
    .RESULT_W(RESULT_W), .MATRIX_W(MATRIX_W),
    .OFFSET_W(OFFSET_W), .FRAC_W(FRAC_W),
    .POSE_W(1), .TIMESTAMP_W(TIMESTAMP_W),
    .REGION_FIFO_DEPTH(REGION_FIFO_DEPTH),
    .SHARED_FIFO_DEPTH(SHARED_FIFO_DEPTH),
    .GUARD_COUNT_W(GUARD_COUNT_W),
    .X_MIN(0), .X_MAX(511), .Y_MIN(0), .Y_MAX(255)
  ) dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_timestamp(occurrence_timestamp),
    .base_sensor_origin_x(base_sensor_origin_x),
    .base_sensor_origin_y(base_sensor_origin_y),
    .arrival_blocked(arrival_blocked),
    .sensor_admission_enabled(sensor_admission_enabled),
    .aer_overrun(aer_overrun),
    .leaf_fifo_overflow(leaf_fifo_overflow),
    .shared_fifo_overflow(shared_fifo_overflow),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_op(cfg_op),
    .cfg_region_x(cfg_region_x), .cfg_region_y(cfg_region_y),
    .cfg_pose_version(cfg_pose_version),
    .cfg_m00(cfg_m00), .cfg_m01(cfg_m01),
    .cfg_m10(cfg_m10), .cfg_m11(cfg_m11),
    .cfg_tx(cfg_tx), .cfg_ty(cfg_ty),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .cfg_busy(cfg_busy), .cfg_awaiting_publish(cfg_awaiting_publish),
    .cfg_publish_pulse(cfg_publish_pulse),
    .cfg_protocol_error(cfg_protocol_error),
    .world_valid(world_valid), .world_ready(world_ready),
    .mapped_valid(mapped_valid), .pose_found(pose_found),
    .in_range(in_range), .region_id_out(region_id_out),
    .sensor_x_out(sensor_x_out), .sensor_y_out(sensor_y_out),
    .polarity_out(polarity_out), .pose_version_out(pose_version_out),
    .occurrence_timestamp_out(occurrence_timestamp_out),
    .world_x_out(world_x_out), .world_y_out(world_y_out),
    .pose_outstanding0(pose_outstanding0),
    .pose_outstanding1(pose_outstanding1),
    .pose_overwrite_ready(pose_overwrite_ready),
    .pose_accounting_error(pose_accounting_error)
  );

  always #5 clk = ~clk;

  integer errors;
  integer cycle_count;
  integer pulses_count;
  integer blocked_count;
  integer aer_overrun_count;
  integer leaf_drop_count;
  integer leaf_drop_pose0_count;
  integer leaf_drop_pose1_count;
  integer world_count;
  integer guard_model0;
  integer guard_model1;
  integer guard_next0;
  integer guard_next1;
  integer max_shared_occupancy;
  integer all256_admission_seen;
  integer shared_stall_seen;
  integer first_publish_block_seen;
  integer last_cfg_fire;
  integer strict_expected;
  integer expected_write;
  integer expected_read;
  integer fairness_active;
  integer fairness_seen;
  integer rewrite_watch;
  integer rewrite_retire_this_edge;
  integer rewrite_retire_edge;
  integer rewrite_commit_edge;
  integer rewrite_commit_seen;
  integer wait_cycles;
  integer region_index;
  integer round_index;
  integer front_index;
  integer pose0_aer_before;
  integer pose0_drop_before;
  integer pose1_aer_before;
  integer pose1_drop_before;

  integer exp_sx [0:MAX_EXPECTED-1];
  integer exp_sy [0:MAX_EXPECTED-1];
  integer exp_pol [0:MAX_EXPECTED-1];
  integer exp_pose [0:MAX_EXPECTED-1];
  reg [TIMESTAMP_W-1:0] exp_time [0:MAX_EXPECTED-1];

  reg held_world_valid;
  reg [REGION_ID_W-1:0] held_region;
  reg [SENSOR_W-1:0] held_sx;
  reg [SENSOR_W-1:0] held_sy;
  reg held_pol;
  reg held_pose;
  reg [TIMESTAMP_W-1:0] held_time;
  reg held_mapped;
  reg held_found;
  reg held_range;
  reg signed [RESULT_W-1:0] held_wx;
  reg signed [RESULT_W-1:0] held_wy;

  function integer popcount256;
    input [255:0] value;
    integer bit_index;
    begin
      popcount256 = 0;
      for (bit_index = 0; bit_index < 256; bit_index = bit_index + 1)
        popcount256 = popcount256 + value[bit_index];
    end
  endfunction

  function integer popcount128;
    input [127:0] value;
    integer bit_index;
    begin
      popcount128 = 0;
      for (bit_index = 0; bit_index < 128; bit_index = bit_index + 1)
        popcount128 = popcount128 + value[bit_index];
    end
  endfunction

  task automatic fail;
    input [8*160-1:0] message;
    begin
      errors = errors + 1;
      if (errors <= 30)
        $display("CHECK_FAIL cycle=%0d %0s", cycle_count, message);
    end
  endtask

  task automatic source_coordinate;
    input integer source_in;
    output integer sx_out;
    output integer sy_out;
    integer source_front;
    integer source_leaf;
    integer leaf_pixel;
    begin
      source_front = source_in / 64;
      source_leaf = (source_in % 64) / 16;
      leaf_pixel = source_in % 16;
      sx_out = BASE_X + (source_front & 1)*8 +
               (source_leaf & 1)*4 + (leaf_pixel & 3);
      sy_out = BASE_Y + ((source_front >> 1) & 1)*8 +
               ((source_leaf >> 1) & 1)*4 + ((leaf_pixel >> 2) & 3);
    end
  endtask

  task automatic queue_expected_source;
    input integer source_in;
    input integer polarity_value;
    input integer pose_in;
    input integer timestamp_in;
    integer sx_value;
    integer sy_value;
    begin
      if (expected_write >= MAX_EXPECTED)
        $fatal(1, "expected queue capacity exceeded");
      source_coordinate(source_in, sx_value, sy_value);
      exp_sx[expected_write] = sx_value;
      exp_sy[expected_write] = sy_value;
      exp_pol[expected_write] = polarity_value;
      exp_pose[expected_write] = pose_in;
      exp_time[expected_write] = timestamp_in;
      expected_write = expected_write + 1;
    end
  endtask

  task automatic set_cfg_coeff;
    input integer x_in;
    input integer y_in;
    input integer pose_in;
    begin
      cfg_region_x = x_in;
      cfg_region_y = y_in;
      cfg_pose_version = pose_in;
      cfg_m00 = Q_ONE;
      cfg_m01 = 0;
      cfg_m10 = 0;
      cfg_m11 = Q_ONE;
      cfg_tx = ((pose_in != 0 ? 100 : 0) + x_in) * Q_ONE;
      cfg_ty = ((pose_in != 0 ? 50 : 0) + y_in) * Q_ONE;
    end
  endtask

  task automatic check_world_output;
    integer expected_region;
    integer expected_wx;
    integer expected_wy;
    begin
      if (held_world_valid) begin
        if (world_valid !== 1'b1 || region_id_out !== held_region ||
            sensor_x_out !== held_sx || sensor_y_out !== held_sy ||
            polarity_out !== held_pol || pose_version_out !== held_pose ||
            occurrence_timestamp_out !== held_time ||
            mapped_valid !== held_mapped || pose_found !== held_found ||
            in_range !== held_range || world_x_out !== held_wx ||
            world_y_out !== held_wy)
          fail("world output changed while stalled");
        shared_stall_seen = shared_stall_seen + 1;
      end

      if (world_valid) begin
        expected_region = (sensor_y_out >> 3)*REGION_COLS +
                          (sensor_x_out >> 3);
        expected_wx = sensor_x_out + (pose_version_out ? 100 : 0) +
                      (sensor_x_out >> 3);
        expected_wy = sensor_y_out + (pose_version_out ? 50 : 0) +
                      (sensor_y_out >> 3);
        if (!mapped_valid || !pose_found || !in_range)
          fail("published coefficient lookup did not map a world event");
        if (region_id_out != expected_region ||
            $signed(world_x_out) != expected_wx ||
            $signed(world_y_out) != expected_wy)
          fail("region ID or region-specific affine result is incorrect");

        if (world_ready) begin
          world_count = world_count + 1;
          if (strict_expected) begin
            if (expected_read >= expected_write) begin
              fail("unexpected world event during strict ordered phase");
            end else begin
              if (sensor_x_out != exp_sx[expected_read] ||
                  sensor_y_out != exp_sy[expected_read] ||
                  polarity_out != exp_pol[expected_read][0] ||
                  pose_version_out != exp_pose[expected_read][0] ||
                  occurrence_timestamp_out !== exp_time[expected_read])
                fail("strict event order/metadata mismatch");
              expected_read = expected_read + 1;
            end
          end
        end
      end

      held_world_valid = world_valid && !world_ready;
      held_region = region_id_out;
      held_sx = sensor_x_out;
      held_sy = sensor_y_out;
      held_pol = polarity_out;
      held_pose = pose_version_out;
      held_time = occurrence_timestamp_out;
      held_mapped = mapped_valid;
      held_found = pose_found;
      held_range = in_range;
      held_wx = world_x_out;
      held_wy = world_y_out;
    end
  endtask

  task automatic sample_before_edge;
    integer pulse_now;
    integer blocked_now;
    integer overrun_now;
    integer leaf_drop_now;
    integer admitted_now;
    integer retire0_now;
    integer retire1_now;
    reg [255:0] expected_blocked;
    begin
      expected_blocked = sensor_admission_enabled ? 256'd0 : arrival;
      if (arrival_blocked !== expected_blocked)
        fail("arrival_blocked disagrees with admission enable");
      if (shared_fifo_overflow)
        fail("lossless shared FIFO reported an overflow");

      pulse_now = popcount256(arrival);
      blocked_now = popcount256(arrival_blocked);
      overrun_now = popcount256(aer_overrun);
      leaf_drop_now = popcount128(leaf_fifo_overflow);
      admitted_now = popcount256(arrival & ~arrival_blocked & ~aer_overrun);
      retire0_now = dut.retire_count0;
      retire1_now = dut.retire_count1;
      pulses_count = pulses_count + pulse_now;
      blocked_count = blocked_count + blocked_now;
      aer_overrun_count = aer_overrun_count + overrun_now;
      leaf_drop_count = leaf_drop_count + leaf_drop_now;
      leaf_drop_pose0_count = leaf_drop_pose0_count + dut.leaf_drop0_total;
      leaf_drop_pose1_count = leaf_drop_pose1_count + dut.leaf_drop1_total;
      if (cfg_valid && cfg_op == CFG_PUBLISH && !active_pose_valid &&
          blocked_now != 0)
        first_publish_block_seen = 1;

      if (blocked_now != 0 && overrun_now != 0)
        fail("blocked arrivals leaked into AER overrun accounting");
      if (leaf_drop_now != dut.leaf_drop0_total + dut.leaf_drop1_total)
        fail("pose-split leaf drop sums do not equal overflow bitmap");
      if (admitted_now != dut.global_admitted_count)
        fail("four 7-bit admission sums did not produce exact 9-bit count");
      if (arrival == {256{1'b1}} && sensor_admission_enabled &&
          aer_overrun == 0) begin
        if (dut.global_admitted_count != 9'd256)
          fail("all-256 simultaneous admission wrapped below 256");
        all256_admission_seen = 1;
      end

      if (fairness_active && dut.merge_valid && dut.merge_ready) begin
        if (dut.merge_source != (fairness_seen & 3))
          fail("four-region merge did not serve 0,1,2,3 order");
        fairness_seen = fairness_seen + 1;
      end

      check_world_output;
      last_cfg_fire = cfg_valid && cfg_ready;
      rewrite_retire_this_edge = 0;
      if (rewrite_watch && dut.terminal_retire &&
          !dut.terminal_retire_pose_version) begin
        rewrite_retire_this_edge = 1;
        rewrite_retire_edge = cycle_count + 1;
        if (cfg_ready || dut.region_wr_commit || pose_overwrite_ready[0])
          fail("old slot became writable on its last-retire edge");
      end
      if (rewrite_watch && dut.region_wr_commit) begin
        rewrite_commit_edge = cycle_count + 1;
        rewrite_commit_seen = rewrite_commit_seen + 1;
      end

      guard_next0 = guard_model0 +
        (active_pose_version ? 0 : admitted_now) - retire0_now;
      guard_next1 = guard_model1 +
        (active_pose_version ? admitted_now : 0) - retire1_now;
      if (guard_next0 < 0 || guard_next1 < 0)
        fail("guard oracle underflowed");
    end
  endtask

  task automatic sample_after_edge;
    begin
      #1;
      guard_model0 = guard_next0;
      guard_model1 = guard_next1;
      if (pose_outstanding0 !== guard_model0[GUARD_COUNT_W-1:0] ||
          pose_outstanding1 !== guard_model1[GUARD_COUNT_W-1:0])
        fail("pose guard count differs from admission/terminal oracle");
      if (dut.shared_fifo_occupancy > max_shared_occupancy)
        max_shared_occupancy = dut.shared_fifo_occupancy;
      if (rewrite_retire_this_edge) begin
        if (!pose_overwrite_ready[0] || !cfg_ready ||
            !dut.region_wr_commit)
          fail("old slot was not offered for rewrite after last retire");
      end
      if (pose_accounting_error)
        fail("pose accounting error asserted");
      if (cfg_protocol_error)
        fail("configuration protocol error asserted");
    end
  endtask

  task automatic step;
    begin
      @(negedge clk);
      #1;
      sample_before_edge;
      @(posedge clk);
      sample_after_edge;
      cycle_count = cycle_count + 1;
    end
  endtask

  task automatic send_cfg;
    input [1:0] op_in;
    input integer x_in;
    input integer y_in;
    input integer pose_in;
    begin
      arrival = 0;
      polarity_in = 0;
      cfg_op = op_in;
      set_cfg_coeff(x_in, y_in, pose_in);
      cfg_valid = 1'b1;
      last_cfg_fire = 0;
      while (!last_cfg_fire)
        step;
      cfg_valid = 1'b0;
    end
  endtask

  task automatic load_epoch_without_publish;
    input integer pose_in;
    integer load_x;
    integer load_y;
    begin
      send_cfg(CFG_BEGIN, 0, 0, pose_in);
      for (region_index = 0; region_index < REGION_COUNT;
           region_index = region_index + 1) begin
        load_x = region_index % REGION_COLS;
        load_y = region_index / REGION_COLS;
        send_cfg(CFG_WRITE, load_x, load_y, pose_in);
      end
      if (!cfg_awaiting_publish)
        fail("full row-major load did not reach publish state");
    end
  endtask

  task automatic idle_steps;
    input integer count_in;
    input integer ready_in;
    integer idle_index;
    begin
      arrival = 0;
      polarity_in = 0;
      cfg_valid = 0;
      world_ready = ready_in;
      for (idle_index = 0; idle_index < count_in;
           idle_index = idle_index + 1) begin
        occurrence_timestamp = occurrence_timestamp + 1'b1;
        step;
      end
    end
  endtask

  task automatic drain_all;
    input integer limit_in;
    begin
      arrival = 0;
      polarity_in = 0;
      cfg_valid = 0;
      world_ready = 1;
      wait_cycles = 0;
      while ((pose_outstanding0 != 0 || pose_outstanding1 != 0 ||
              world_valid || dut.shared_fifo_occupancy != 0) &&
             wait_cycles < limit_in) begin
        occurrence_timestamp = occurrence_timestamp + 1'b1;
        step;
        wait_cycles = wait_cycles + 1;
      end
      idle_steps(3, 1);
      if (pose_outstanding0 != 0 || pose_outstanding1 != 0 || world_valid)
        fail("pipeline and guard did not fully drain");
    end
  endtask

  task automatic drive_dense_pressure;
    input integer first_time;
    integer dense_index;
    begin
      strict_expected = 0;
      cfg_valid = 0;
      world_ready = 0;
      for (dense_index = 0; dense_index < 12;
           dense_index = dense_index + 1) begin
        arrival = {256{1'b1}};
        polarity_in = dense_index[0]
          ? {128{2'b10}} : {128{2'b01}};
        occurrence_timestamp = first_time + dense_index;
        step;
      end
      idle_steps(10, 0);
      drain_all(5000);
      strict_expected = 1;
    end
  endtask

  reg [255:0] event_mask;
  reg [255:0] event_polarity;
  integer local_source [0:3];
  integer chosen_source;

  initial begin
    clk = 0;
    rst = 1;
    arrival = 0;
    polarity_in = 0;
    occurrence_timestamp = 0;
    base_sensor_origin_x = BASE_X;
    base_sensor_origin_y = BASE_Y;
    cfg_valid = 0;
    cfg_op = CFG_BEGIN;
    cfg_region_x = 0;
    cfg_region_y = 0;
    cfg_pose_version = 0;
    cfg_m00 = Q_ONE;
    cfg_m01 = 0;
    cfg_m10 = 0;
    cfg_m11 = Q_ONE;
    cfg_tx = 0;
    cfg_ty = 0;
    world_ready = 1;
    errors = 0;
    cycle_count = 0;
    pulses_count = 0;
    blocked_count = 0;
    aer_overrun_count = 0;
    leaf_drop_count = 0;
    leaf_drop_pose0_count = 0;
    leaf_drop_pose1_count = 0;
    world_count = 0;
    guard_model0 = 0;
    guard_model1 = 0;
    guard_next0 = 0;
    guard_next1 = 0;
    max_shared_occupancy = 0;
    all256_admission_seen = 0;
    shared_stall_seen = 0;
    first_publish_block_seen = 0;
    last_cfg_fire = 0;
    strict_expected = 1;
    expected_write = 0;
    expected_read = 0;
    fairness_active = 0;
    fairness_seen = 0;
    rewrite_watch = 0;
    rewrite_retire_this_edge = 0;
    rewrite_retire_edge = -1;
    rewrite_commit_edge = -1;
    rewrite_commit_seen = 0;
    held_world_valid = 0;
    local_source[0] = 0;
    local_source[1] = 23;
    local_source[2] = 41;
    local_source[3] = 62;

    repeat (4) @(posedge clk);
    #1 rst = 0;

    // A pulse interface has no retry: before the first publish it is reported
    // as blocked and never reaches AER storage.
    arrival = 256'd1;
    polarity_in = 0;
    occurrence_timestamp = 35'd10;
    step;
    if (arrival_blocked != arrival || sensor_admission_enabled)
      fail("pre-publish pulse was not blocked");
    arrival = 0;

    load_epoch_without_publish(0);

    // The first PUBLISH edge still sees active_valid=0, so this pulse is also
    // blocked; admission starts only in the following cycle.
    cfg_op = CFG_PUBLISH;
    set_cfg_coeff(0, 0, 0);
    cfg_valid = 1;
    arrival = 256'd2;
    polarity_in = 256'd2;
    occurrence_timestamp = 35'd20;
    last_cfg_fire = 0;
    step;
    if (!last_cfg_fire || !active_pose_valid || active_pose_version != 0)
      fail("first coefficient epoch did not publish");
    if (arrival_blocked[1])
      first_publish_block_seen = 1;
    cfg_valid = 0;
    arrival = 0;
    idle_steps(1, 1);

    // One event from each 8x8 region proves the 2x2 global placement, four
    // distinct region coefficients, and initial 0,1,2,3 merge fairness.
    event_mask = 0;
    event_polarity = 0;
    for (front_index = 0; front_index < 4;
         front_index = front_index + 1) begin
      chosen_source = front_index*64 + local_source[front_index];
      event_mask[chosen_source] = 1'b1;
      event_polarity[chosen_source] = front_index[0];
      queue_expected_source(chosen_source, front_index & 1, 0, 1000);
    end
    fairness_active = 1;
    fairness_seen = 0;
    arrival = event_mask;
    polarity_in = event_polarity;
    occurrence_timestamp = 35'd1000;
    world_ready = 1;
    step;
    arrival = 0;
    wait_cycles = 0;
    while ((fairness_seen < 4 || expected_read < expected_write) &&
           wait_cycles < 100) begin
      step;
      wait_cycles = wait_cycles + 1;
    end
    fairness_active = 0;
    if (fairness_seen != 4 || expected_read != expected_write)
      fail("four-region simultaneous fairness/order phase did not finish");
    drain_all(100);

    // Three fair rounds fill the shared depth-8 FIFO behind a stalled affine
    // output without disabling pulse admission or creating a shared drop.
    pose0_aer_before = aer_overrun_count;
    pose0_drop_before = leaf_drop_count;
    world_ready = 0;
    for (round_index = 0; round_index < 3;
         round_index = round_index + 1) begin
      event_mask = 0;
      event_polarity = 0;
      for (front_index = 0; front_index < 4;
           front_index = front_index + 1) begin
        chosen_source = front_index*64 + round_index + 1;
        event_mask[chosen_source] = 1'b1;
        event_polarity[chosen_source] = (round_index + front_index) & 1;
        queue_expected_source(chosen_source,
                              (round_index + front_index) & 1,
                              0, 1100 + round_index);
      end
      arrival = event_mask;
      polarity_in = event_polarity;
      occurrence_timestamp = 1100 + round_index;
      step;
      idle_steps(2, 0);
    end
    idle_steps(30, 0);
    if (!sensor_admission_enabled)
      fail("world backpressure incorrectly disabled pulse admission");
    if (max_shared_occupancy != SHARED_FIFO_DEPTH)
      fail("long world stall did not fill the shared depth-8 FIFO");
    if (aer_overrun_count != pose0_aer_before ||
        leaf_drop_count != pose0_drop_before)
      fail("controlled shared-FIFO fill unexpectedly lost an event");
    drain_all(500);
    if (expected_read != expected_write)
      fail("ordered long-stall events did not all emerge");

    // Force both allowed loss boundaries under epoch 0.
    pose0_aer_before = aer_overrun_count;
    pose0_drop_before = leaf_drop_pose0_count;
    drive_dense_pressure(2000);
    if (aer_overrun_count == pose0_aer_before ||
        leaf_drop_pose0_count == pose0_drop_before)
      fail("epoch-0 pressure did not force AER and leaf-FIFO losses");

    // Fully load epoch 1 while epoch 0 remains active.
    load_epoch_without_publish(1);

    // An event on the epoch-1 PUBLISH edge is admitted with old epoch 0.
    // The following same-source pulse is tagged epoch 1, preserving order.
    chosen_source = 5;
    cfg_op = CFG_PUBLISH;
    set_cfg_coeff(0, 0, 1);
    cfg_valid = 1;
    arrival = 0;
    arrival[chosen_source] = 1'b1;
    polarity_in = 0;
    polarity_in[chosen_source] = 1'b1;
    occurrence_timestamp = 35'd5000;
    queue_expected_source(chosen_source, 1, 0, 5000);
    last_cfg_fire = 0;
    step;
    if (!last_cfg_fire || active_pose_version != 1)
      fail("epoch 1 did not publish on the old-tag admission edge");

    // BEGIN reuse of old slot and admit the new-tag successor together.
    cfg_op = CFG_BEGIN;
    set_cfg_coeff(0, 0, 0);
    cfg_valid = 1;
    arrival = 0;
    arrival[chosen_source] = 1'b1;
    polarity_in = 0;
    occurrence_timestamp = 35'd5001;
    queue_expected_source(chosen_source, 0, 1, 5001);
    last_cfg_fire = 0;
    step;
    if (!last_cfg_fire || !cfg_busy)
      fail("old-slot reload BEGIN was not accepted");

    // Hold WRITE(0,0) until the old event reaches terminal_retire.  The guard
    // must keep ready low on that edge and allow the write exactly next edge.
    cfg_op = CFG_WRITE;
    set_cfg_coeff(0, 0, 0);
    cfg_valid = 1;
    arrival = 0;
    rewrite_watch = 1;
    last_cfg_fire = 0;
    wait_cycles = 0;
    while (!last_cfg_fire && wait_cycles < 100) begin
      step;
      wait_cycles = wait_cycles + 1;
    end
    cfg_valid = 0;
    rewrite_watch = 0;
    if (!last_cfg_fire || rewrite_retire_edge < 0 ||
        rewrite_commit_seen != 1 ||
        rewrite_commit_edge != rewrite_retire_edge + 1)
      fail("old slot was not rewritten exactly one edge after last retire");
    send_cfg(CFG_ABORT, 0, 0, 0);
    drain_all(500);
    if (expected_read != expected_write)
      fail("publish-edge old/new tagged events did not emerge in order");

    // Force the same two loss boundaries under epoch 1 as well.
    pose1_aer_before = aer_overrun_count;
    pose1_drop_before = leaf_drop_pose1_count;
    drive_dense_pressure(6000);
    if (aer_overrun_count == pose1_aer_before ||
        leaf_drop_pose1_count == pose1_drop_before)
      fail("epoch-1 pressure did not force AER and leaf-FIFO losses");

    drain_all(5000);
    if (guard_model0 != 0 || guard_model1 != 0 ||
        pose_outstanding0 != 0 || pose_outstanding1 != 0)
      fail("pose guard retained references after final drain");
    if (pulses_count != blocked_count + aer_overrun_count +
                        leaf_drop_count + world_count)
      fail("pulses != blocked + AER overrun + leaf drop + world");
    if (!all256_admission_seen || !first_publish_block_seen ||
        shared_stall_seen == 0 || max_shared_occupancy != 8 ||
        leaf_drop_pose0_count == 0 || leaf_drop_pose1_count == 0 ||
        aer_overrun_count == 0)
      fail("required directed coverage was not reached");
    if (shared_fifo_overflow || pose_accounting_error ||
        cfg_protocol_error)
      fail("a sticky error remained at completion");

    $display("TX256_SHARED_COUNTS pulses=%0d blocked=%0d aer_overrun=%0d leaf_drop=%0d world=%0d",
             pulses_count, blocked_count, aer_overrun_count,
             leaf_drop_count, world_count);
    $display("TX256_SHARED_COVERAGE drop0=%0d drop1=%0d shared_peak=%0d stalls=%0d fairness=%0d rewrite_retire=%0d rewrite_commit=%0d",
             leaf_drop_pose0_count, leaf_drop_pose1_count,
             max_shared_occupancy, shared_stall_seen, fairness_seen,
             rewrite_retire_edge, rewrite_commit_edge);
    if (errors == 0) begin
      $display("AER_TX256_REGION_SHARED_AFFINE_PASS");
      $finish;
    end else begin
      $fatal(1, "AER_TX256_REGION_SHARED_AFFINE_FAIL errors=%0d", errors);
    end
  end
endmodule
