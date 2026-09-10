`timescale 1ns/1ps

module tb_pose_inflight_guard8;
  localparam integer POSE_W = 3;
  localparam integer COUNT_W = 5;
  localparam integer RETIRE_LANES = 8;
`ifdef POSE_GUARD_ACCEPT_SOURCES
  localparam integer ACCEPT_SOURCES = `POSE_GUARD_ACCEPT_SOURCES;
`else
  localparam integer ACCEPT_SOURCES = 16;
`endif
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer MAX_COUNT = (1 << COUNT_W) - 1;
  localparam integer RANDOM_CYCLES = 20000;

  reg clk = 0;
  reg rst;
  reg [ACCEPT_SOURCES-1:0] accepted_mask;
  reg [POSE_W-1:0] accepted_pose_version;
  reg [RETIRE_LANES-1:0] retire_valid;
  reg [(RETIRE_LANES*POSE_W)-1:0] retire_pose_version_flat;
  reg pose_wr_req;
  reg [POSE_W-1:0] pose_wr_id;
  wire pose_wr_ready;
  wire pose_wr_commit;
  wire pose_wr_rejected;
  wire accounting_error;

  pose_inflight_guard8 #(
    .POSE_W(POSE_W), .COUNT_W(COUNT_W), .RETIRE_LANES(RETIRE_LANES),
    .ACCEPT_SOURCES(ACCEPT_SOURCES)
  ) dut (
    .clk(clk), .rst(rst),
    .accepted_mask(accepted_mask),
    .accepted_pose_version(accepted_pose_version),
    .retire_valid(retire_valid),
    .retire_pose_version_flat(retire_pose_version_flat),
    .pose_wr_req(pose_wr_req), .pose_wr_id(pose_wr_id),
    .pose_wr_ready(pose_wr_ready),
    .pose_wr_commit(pose_wr_commit), .pose_wr_rejected(pose_wr_rejected),
    .accounting_error(accounting_error)
  );

  always #5 clk = ~clk;

  integer model [0:POSE_IDS-1];
  integer next_model [0:POSE_IDS-1];
  integer available [0:POSE_IDS-1];
  integer errors;
  integer expected_error;
  integer commits;
  integer rejects;
  integer cycle_no;
  integer seed;
  integer i;
  integer lane;
  integer scan;
  integer candidate;
  integer start_id;
  integer found;
  integer accepted_n;
  integer first_retire_id;
  integer have_first_retire;
  integer expected_commit;
  integer expected_reject;
  integer same_cycle_write_accept_seen;
  integer last_retire_reject_seen;
  integer mixed_retire_seen;
  integer wrap_seen;
  integer reuse_seen;
  integer previous_accept_valid;
  integer previous_accept_id;
  integer overflow_round;
  reg [POSE_IDS-1:0] committed_before;
  reg [POSE_IDS-1:0] accepted_id_seen;
  reg [POSE_IDS-1:0] retired_id_seen;
  reg [POSE_IDS-1:0] model_poisoned;
  reg [POSE_IDS-1:0] next_poisoned;

  function integer popcount_accepted;
    input [ACCEPT_SOURCES-1:0] bits;
    integer bit_idx;
    begin
      popcount_accepted = 0;
      for (bit_idx = 0; bit_idx < ACCEPT_SOURCES; bit_idx = bit_idx + 1)
        popcount_accepted = popcount_accepted + bits[bit_idx];
    end
  endfunction

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

  task automatic clear_inputs;
    begin
      accepted_mask = 16'd0;
      accepted_pose_version = 0;
      retire_valid = 0;
      retire_pose_version_flat = 0;
      pose_wr_req = 1'b0;
      pose_wr_id = 0;
    end
  endtask

  task automatic compare_counts;
    begin
      for (i = 0; i < POSE_IDS; i = i + 1) begin
        if (dut.outstanding[i] !== model[i][COUNT_W-1:0]) begin
          errors = errors + 1;
          $display("COUNT_FAIL cycle=%0d id=%0d dut=%0d model=%0d",
            cycle_no, i, dut.outstanding[i], model[i]);
        end
        if (dut.poisoned[i] !== model_poisoned[i]) begin
          errors = errors + 1;
          $display("POISON_FAIL cycle=%0d id=%0d dut=%0b model=%0b",
            cycle_no, i, dut.poisoned[i], model_poisoned[i]);
        end
      end
    end
  endtask

  task automatic reset_guard;
    begin
      @(negedge clk);
      rst = 1'b1;
      accepted_mask = 16'hffff;
      accepted_pose_version = {POSE_W{1'b1}};
      retire_valid = {RETIRE_LANES{1'b1}};
      retire_pose_version_flat = {(RETIRE_LANES*POSE_W){1'b1}};
      pose_wr_req = 1'b1;
      pose_wr_id = {POSE_W{1'b1}};
      #1;
      check(pose_wr_commit === 1'b0 && pose_wr_rejected === 1'b0,
        "writes are disabled during reset");
      check(pose_wr_ready === 1'b0, "write ready is low during reset");
      @(posedge clk);
      #1;
      for (i = 0; i < POSE_IDS; i = i + 1)
        model[i] = 0;
      model_poisoned = 0;
      expected_error = 0;
      compare_counts();
      check(accounting_error === 1'b0, "reset clears sticky accounting error");
      @(negedge clk);
      rst = 1'b0;
      clear_inputs();
    end
  endtask

  task automatic step;
    begin
      #1;
      expected_commit = pose_wr_req && (model[pose_wr_id] == 0) &&
                        !model_poisoned[pose_wr_id];
      expected_reject = pose_wr_req && ((model[pose_wr_id] != 0) ||
                        model_poisoned[pose_wr_id]);
      check(pose_wr_ready === ((model[pose_wr_id] == 0) &&
                              !model_poisoned[pose_wr_id]),
        "pose write ready reflects current ID count and poison state");
      check(pose_wr_commit === expected_commit[0], "pose write commit decision");
      check(pose_wr_rejected === expected_reject[0], "pose write rejection decision");
      check(!(pose_wr_commit && pose_wr_rejected), "commit and reject are exclusive");
      if (expected_commit) begin
        commits = commits + 1;
        if (committed_before[pose_wr_id]) reuse_seen = 1;
        committed_before[pose_wr_id] = 1'b1;
      end
      if (expected_reject) rejects = rejects + 1;

      next_poisoned = model_poisoned;
      for (i = 0; i < POSE_IDS; i = i + 1)
        next_model[i] = model[i];
      accepted_n = popcount_accepted(accepted_mask);
      next_model[accepted_pose_version] =
        next_model[accepted_pose_version] + accepted_n;
      if (accepted_n != 0) begin
        accepted_id_seen[accepted_pose_version] = 1'b1;
        if (previous_accept_valid && previous_accept_id == POSE_IDS-1 &&
            accepted_pose_version == 0)
          wrap_seen = 1;
        previous_accept_valid = 1;
        previous_accept_id = accepted_pose_version;
      end
      if (expected_commit && accepted_n != 0 &&
          accepted_pose_version == pose_wr_id)
        same_cycle_write_accept_seen = 1;

      have_first_retire = 0;
      first_retire_id = 0;
      for (lane = 0; lane < RETIRE_LANES; lane = lane + 1) begin
        if (retire_valid[lane]) begin
          candidate = retire_pose_version_flat[(lane*POSE_W) +: POSE_W];
          next_model[candidate] = next_model[candidate] - 1;
          retired_id_seen[candidate] = 1'b1;
          if (have_first_retire && candidate != first_retire_id)
            mixed_retire_seen = 1;
          if (!have_first_retire) begin
            have_first_retire = 1;
            first_retire_id = candidate;
          end
        end
      end

      if (expected_reject && next_model[pose_wr_id] == 0)
        last_retire_reject_seen = 1;
      for (i = 0; i < POSE_IDS; i = i + 1) begin
        if (next_model[i] < 0) begin
          next_model[i] = 0;
          next_poisoned[i] = 1'b1;
          expected_error = 1;
        end else if (next_model[i] > MAX_COUNT) begin
          next_model[i] = MAX_COUNT;
          next_poisoned[i] = 1'b1;
          expected_error = 1;
        end
      end

      @(posedge clk);
      #1;
      for (i = 0; i < POSE_IDS; i = i + 1)
        model[i] = next_model[i];
      model_poisoned = next_poisoned;
      compare_counts();
      check(accounting_error === expected_error[0], "sticky accounting error state");
    end
  endtask

  initial begin
    rst = 1'b1;
    clear_inputs();
    errors = 0;
    expected_error = 0;
    commits = 0;
    rejects = 0;
    cycle_no = 0;
    seed = 32'h2468ace1;
    same_cycle_write_accept_seen = 0;
    last_retire_reject_seen = 0;
    mixed_retire_seen = 0;
    wrap_seen = 0;
    reuse_seen = 0;
    previous_accept_valid = 0;
    previous_accept_id = 0;
    committed_before = 0;
    accepted_id_seen = 0;
    retired_id_seen = 0;
    for (i = 0; i < POSE_IDS; i = i + 1) model[i] = 0;

    reset_guard();

    // Empty ID: its pose write and first accepted events share the edge safely.
    cycle_no = cycle_no + 1;
    accepted_mask = 0;
    accepted_mask[0] = 1'b1;
    accepted_mask[2] = 1'b1;
    accepted_mask[ACCEPT_SOURCES-1] = 1'b1;
    accepted_pose_version = 3;
    pose_wr_req = 1'b1;
    pose_wr_id = 3;
    step();
    check(model[3] == 3, "three accepts are counted for pose 3");

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    pose_wr_req = 1'b1;
    pose_wr_id = 3;
    step();
    check(rejects != 0, "busy pose write is explicitly rejected");

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    accepted_mask = 16'h0003;
    accepted_pose_version = 5;
    pose_wr_req = 1'b1;
    pose_wr_id = 5;
    step();

    // Retire IDs 3,5,3 on the same edge.
    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    retire_valid = 8'b00000111;
    retire_pose_version_flat[0*POSE_W +: POSE_W] = 3;
    retire_pose_version_flat[1*POSE_W +: POSE_W] = 5;
    retire_pose_version_flat[2*POSE_W +: POSE_W] = 3;
    step();
    check(model[3] == 1 && model[5] == 1, "mixed retire IDs decrement independently");

    // Last retire does not make an overwrite safe until the following cycle.
    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    retire_valid = 8'b00000011;
    retire_pose_version_flat[0*POSE_W +: POSE_W] = 3;
    retire_pose_version_flat[1*POSE_W +: POSE_W] = 5;
    pose_wr_req = 1'b1;
    pose_wr_id = 3;
    step();
    check(model[3] == 0 && last_retire_reject_seen,
      "last-retire edge rejects overwrite");

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    pose_wr_req = 1'b1;
    pose_wr_id = 3;
    step();

    // Version wrap 7->0 and later reuse of version 7.
    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    accepted_mask = 16'h0001;
    accepted_pose_version = 7;
    pose_wr_req = 1'b1;
    pose_wr_id = 7;
    step();

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    accepted_mask = 16'h0001;
    accepted_pose_version = 0;
    pose_wr_req = 1'b1;
    pose_wr_id = 0;
    step();

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    retire_valid = 8'b00000011;
    retire_pose_version_flat[0*POSE_W +: POSE_W] = 7;
    retire_pose_version_flat[1*POSE_W +: POSE_W] = 0;
    pose_wr_req = 1'b1;
    pose_wr_id = 7;
    step();

    @(negedge clk); clear_inputs();
    cycle_no = cycle_no + 1;
    pose_wr_req = 1'b1;
    pose_wr_id = 7;
    step();

    // Valid randomized accounting: retire only IDs currently outstanding and
    // avoid count overflow so accounting_error must remain clear.
    for (cycle_no = cycle_no + 1;
         cycle_no <= RANDOM_CYCLES;
         cycle_no = cycle_no + 1) begin
      @(negedge clk);
      clear_inputs();
      accepted_mask = $random(seed) & $random(seed) &
        $random(seed) & $random(seed);
      accepted_pose_version = $random(seed);
      accepted_n = popcount_accepted(accepted_mask);
      if (model[accepted_pose_version] + accepted_n > MAX_COUNT)
        accepted_mask = 16'd0;

      for (i = 0; i < POSE_IDS; i = i + 1)
        available[i] = model[i];
      for (lane = 0; lane < RETIRE_LANES; lane = lane + 1) begin
        if (($random(seed) & 3) != 0) begin
          start_id = $random(seed) & (POSE_IDS-1);
          found = 0;
          for (scan = 0; scan < POSE_IDS; scan = scan + 1) begin
            candidate = (start_id + scan) & (POSE_IDS-1);
            if (!found && available[candidate] > 0) begin
              retire_valid[lane] = 1'b1;
              retire_pose_version_flat[(lane*POSE_W) +: POSE_W] = candidate;
              available[candidate] = available[candidate] - 1;
              found = 1;
            end
          end
        end
      end
      pose_wr_req = (($random(seed) & 7) == 0);
      pose_wr_id = $random(seed);
      step();
    end
    check(expected_error == 0, "valid random traffic has no accounting error");
    check(accepted_id_seen == {POSE_IDS{1'b1}}, "random traffic accepted every pose ID");
    check(retired_id_seen == {POSE_IDS{1'b1}}, "random traffic retired every pose ID");

    // Underflow is clamped/reported and poisons the ID until reset.  Blocking
    // overwrite is fail-safe because the true number of references is unknown.
    reset_guard();
    cycle_no = cycle_no + 1;
    retire_valid = 1;
    retire_pose_version_flat[0 +: POSE_W] = 2;
    step();
    check(model[2] == 0 && model_poisoned[2] && accounting_error,
      "retire underflow is detected and poisons the ID");
    @(negedge clk); clear_inputs();
    pose_wr_req = 1'b1;
    pose_wr_id = 2;
    cycle_no = cycle_no + 1;
    step();
    check(!pose_wr_commit && pose_wr_rejected && accounting_error,
      "poisoned zero-count ID remains blocked until reset");

    // Repeated all-source accepts exceed the count representation.
    reset_guard();
    cycle_no = cycle_no + 1;
    accepted_mask = {ACCEPT_SOURCES{1'b1}};
    accepted_pose_version = 6;
    step();
    check(model[6] == ACCEPT_SOURCES && !accounting_error,
      "first all-source accept fits");
    for (overflow_round = 1;
         overflow_round < (MAX_COUNT/ACCEPT_SOURCES)+1;
         overflow_round = overflow_round + 1) begin
      @(negedge clk); clear_inputs();
      cycle_no = cycle_no + 1;
      accepted_mask = {ACCEPT_SOURCES{1'b1}};
      accepted_pose_version = 6;
      step();
    end
    check(model[6] == MAX_COUNT && model_poisoned[6] && accounting_error,
      "count overflow saturates, is detected, and poisons the ID");

    reset_guard();
    check(wrap_seen, "pose version wrap 7 to 0 was exercised");
    check(reuse_seen, "a drained pose ID was safely reused");
    check(same_cycle_write_accept_seen,
      "same-cycle first write plus accepted event was exercised");
    check(last_retire_reject_seen,
      "last-retire overwrite rejection was exercised");
    check(mixed_retire_seen, "mixed retire IDs were exercised");
    check(commits > 0 && rejects > 0, "both write outcomes were exercised");

    $display("POSE_GUARD_SUMMARY cycles=%0d commits=%0d rejects=%0d errors=%0d",
      RANDOM_CYCLES, commits, rejects, errors);
    if (errors == 0) begin
      $display("POSE_INFLIGHT_GUARD8_PASS");
      $finish;
    end else begin
      $fatal(1, "POSE_INFLIGHT_GUARD8_FAIL errors=%0d", errors);
    end
  end
endmodule
