`timescale 1ns/1ps

module tb_pose_epoch_count_guard2;
  localparam integer COUNT_W = 5;
  localparam integer DELTA_W = 4;
  localparam integer MAX_COUNT = (1 << COUNT_W) - 1;
  localparam integer MAX_DELTA = (1 << DELTA_W) - 1;
  localparam integer RANDOM_CYCLES = 20000;

  reg clk;
  reg rst;
  reg accept_pose_id;
  reg [DELTA_W-1:0] accept_count;
  reg [DELTA_W-1:0] retire_count0;
  reg [DELTA_W-1:0] retire_count1;
  wire [COUNT_W-1:0] outstanding0;
  wire [COUNT_W-1:0] outstanding1;
  wire [1:0] idle;
  wire [1:0] overwrite_ready;
  wire accounting_error;

  pose_epoch_count_guard2 #(
    .COUNT_W(COUNT_W),
    .DELTA_W(DELTA_W)
  ) dut (
    .clk(clk),
    .rst(rst),
    .accept_pose_id(accept_pose_id),
    .accept_count(accept_count),
    .retire_count0(retire_count0),
    .retire_count1(retire_count1),
    .outstanding0(outstanding0),
    .outstanding1(outstanding1),
    .idle(idle),
    .overwrite_ready(overwrite_ready),
    .accounting_error(accounting_error)
  );

  always #5 clk = ~clk;

  integer errors;
  integer cycle_no;
  integer seed;
  integer model_count0;
  integer model_count1;
  integer model_poison0;
  integer model_poison1;
  integer model_error;
  integer accept0;
  integer accept1;
  integer raw_next0;
  integer raw_next1;
  integer error0;
  integer error1;
  integer expected_ready0;
  integer expected_ready1;
  integer random_value;
  integer available0;
  integer available1;
  integer random_cycle;
  integer saw_accept0;
  integer saw_accept1;
  integer saw_both_update;
  integer saw_ready0;
  integer saw_ready1;

  task check;
    input condition;
    input [639:0] message;
    begin
      if (condition !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL cycle=%0d: %0s", cycle_no, message);
      end
    end
  endtask

  task clear_inputs;
    begin
      accept_pose_id = 1'b0;
      accept_count = {DELTA_W{1'b0}};
      retire_count0 = {DELTA_W{1'b0}};
      retire_count1 = {DELTA_W{1'b0}};
    end
  endtask

  task compare_registered_state;
    begin
      check(outstanding0 === model_count0[COUNT_W-1:0],
            "pose 0 outstanding count matches shadow");
      check(outstanding1 === model_count1[COUNT_W-1:0],
            "pose 1 outstanding count matches shadow");
      check(idle[0] === (model_count0 == 0),
            "pose 0 idle reflects registered count");
      check(idle[1] === (model_count1 == 0),
            "pose 1 idle reflects registered count");
      check(dut.poisoned[0] === model_poison0[0],
            "pose 0 poison matches shadow");
      check(dut.poisoned[1] === model_poison1[0],
            "pose 1 poison matches shadow");
      check(accounting_error === model_error[0],
            "sticky accounting error matches shadow");
      check(model_count0 >= 0 && model_count0 <= MAX_COUNT,
            "pose 0 counter stays saturated in range");
      check(model_count1 >= 0 && model_count1 <= MAX_COUNT,
            "pose 1 counter stays saturated in range");
    end
  endtask

  task step;
    begin
      cycle_no = cycle_no + 1;
      #1;
      accept0 = (!accept_pose_id) ? accept_count : 0;
      accept1 = accept_pose_id ? accept_count : 0;
      raw_next0 = model_count0 + accept0 - retire_count0;
      raw_next1 = model_count1 + accept1 - retire_count1;
      error0 = (raw_next0 < 0) || (raw_next0 > MAX_COUNT);
      error1 = (raw_next1 < 0) || (raw_next1 > MAX_COUNT);
      expected_ready0 = (model_count0 == 0) && !model_poison0 &&
                        (accept0 == 0) && !error0;
      expected_ready1 = (model_count1 == 0) && !model_poison1 &&
                        (accept1 == 0) && !error1;

      check(idle[0] === (model_count0 == 0),
            "pose 0 pre-edge idle is registered state");
      check(idle[1] === (model_count1 == 0),
            "pose 1 pre-edge idle is registered state");
      check(overwrite_ready[0] === expected_ready0[0],
            "pose 0 overwrite readiness is fail-safe");
      check(overwrite_ready[1] === expected_ready1[0],
            "pose 1 overwrite readiness is fail-safe");
      check(!(overwrite_ready[0] &&
              ((model_count0 != 0) || model_poison0 || (accept0 != 0) || error0)),
            "pose 0 ready invariant");
      check(!(overwrite_ready[1] &&
              ((model_count1 != 0) || model_poison1 || (accept1 != 0) || error1)),
            "pose 1 ready invariant");

      if (accept0 != 0) saw_accept0 = 1;
      if (accept1 != 0) saw_accept1 = 1;
      if (((accept0 != 0) || (retire_count0 != 0)) &&
          ((accept1 != 0) || (retire_count1 != 0)))
        saw_both_update = 1;
      if (overwrite_ready[0]) saw_ready0 = 1;
      if (overwrite_ready[1]) saw_ready1 = 1;

      @(posedge clk);
      #1;
      if (raw_next0 < 0) begin
        model_count0 = 0;
        model_poison0 = 1;
      end else if (raw_next0 > MAX_COUNT) begin
        model_count0 = MAX_COUNT;
        model_poison0 = 1;
      end else begin
        model_count0 = raw_next0;
      end
      if (raw_next1 < 0) begin
        model_count1 = 0;
        model_poison1 = 1;
      end else if (raw_next1 > MAX_COUNT) begin
        model_count1 = MAX_COUNT;
        model_poison1 = 1;
      end else begin
        model_count1 = raw_next1;
      end
      model_error = model_error || error0 || error1;
      compare_registered_state();
    end
  endtask

  task reset_guard;
    begin
      @(negedge clk);
      rst = 1'b1;
      accept_pose_id = 1'b1;
      accept_count = {DELTA_W{1'b1}};
      retire_count0 = {DELTA_W{1'b1}};
      retire_count1 = {DELTA_W{1'b1}};
      #1;
      check(overwrite_ready === 2'b00,
            "reset blocks both overwrite slots");
      @(posedge clk);
      #1;
      model_count0 = 0;
      model_count1 = 0;
      model_poison0 = 0;
      model_poison1 = 0;
      model_error = 0;
      compare_registered_state();
      @(negedge clk);
      rst = 1'b0;
      clear_inputs();
      #1;
      check(overwrite_ready === 2'b11,
            "both empty slots become writable after reset");
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    clear_inputs();
    errors = 0;
    cycle_no = 0;
    seed = 32'h31c0ffee;
    model_count0 = 0;
    model_count1 = 0;
    model_poison0 = 0;
    model_poison1 = 0;
    model_error = 0;
    saw_accept0 = 0;
    saw_accept1 = 0;
    saw_both_update = 0;
    saw_ready0 = 0;
    saw_ready1 = 0;

    reset_guard();

    // A same-edge first accept blocks overwriting even though idle is still
    // the registered zero state.
    accept_pose_id = 1'b0;
    accept_count = 4'd3;
    step();
    check(model_count0 == 3 && !idle[0],
          "pose 0 first accepts are counted");

    // Accept and retire of the same pose are one atomic signed delta.
    @(negedge clk);
    clear_inputs();
    accept_pose_id = 1'b0;
    accept_count = 4'd5;
    retire_count0 = 4'd6;
    step();
    check(model_count0 == 2 && !model_error,
          "same-pose accept plus retire computes current+accept-retire");

    // One active accept pose and both retire counters update independently.
    @(negedge clk);
    clear_inputs();
    accept_pose_id = 1'b1;
    accept_count = 4'd4;
    retire_count0 = 4'd1;
    step();
    check(model_count0 == 1 && model_count1 == 4,
          "both pose slots update on the same edge");

    // The final retire edge is not writable; readiness rises only after it.
    @(negedge clk);
    clear_inputs();
    retire_count0 = 4'd1;
    #1;
    check(overwrite_ready[0] === 1'b0,
          "last-retire edge remains blocked");
    step();
    check(model_count0 == 0 && idle[0],
          "last retire drains pose 0");
    @(negedge clk);
    clear_inputs();
    #1;
    check(overwrite_ready[0] === 1'b1,
          "drained pose becomes writable on the next cycle");

    // A zero-net accept/retire on an idle pose is legal but still blocks a
    // same-edge overwrite because a new accepted event exists on that edge.
    accept_pose_id = 1'b0;
    accept_count = 4'd5;
    retire_count0 = 4'd5;
    #1;
    check(idle[0] && !overwrite_ready[0],
          "zero-net same-edge accept still blocks overwrite");
    step();
    check(model_count0 == 0 && !model_error,
          "balanced accept and retire do not underflow");

    // Drain pose 1 before randomized valid traffic.
    @(negedge clk);
    clear_inputs();
    retire_count1 = 4'd4;
    step();
    @(negedge clk);
    clear_inputs();

    // Random shadow-model phase: all generated deltas are valid so neither
    // poison nor the sticky error may fire.
    for (random_cycle = 0;
         random_cycle < RANDOM_CYCLES;
         random_cycle = random_cycle + 1) begin
      accept_pose_id = $random(seed) & 1;
      random_value = $random(seed);
      accept_count = random_value & MAX_DELTA;
      if (!accept_pose_id && model_count0 + accept_count > MAX_COUNT)
        accept_count = 0;
      if (accept_pose_id && model_count1 + accept_count > MAX_COUNT)
        accept_count = 0;

      available0 = model_count0 + ((!accept_pose_id) ? accept_count : 0);
      available1 = model_count1 + (accept_pose_id ? accept_count : 0);
      random_value = $random(seed);
      retire_count0 = random_value & MAX_DELTA;
      if (retire_count0 > available0)
        retire_count0 = available0;
      random_value = $random(seed);
      retire_count1 = random_value & MAX_DELTA;
      if (retire_count1 > available1)
        retire_count1 = available1;

      step();
      @(negedge clk);
      clear_inputs();
    end
    check(!model_error && !model_poison0 && !model_poison1,
          "valid random traffic stays error-free");

    // Underflow poisons only the offending slot and clamps it to zero.
    reset_guard();
    retire_count1 = 4'd1;
    #1;
    check(!overwrite_ready[1],
          "pending underflow blocks overwrite immediately");
    step();
    check(model_count1 == 0 && model_poison1 && model_error,
          "underflow clamps and poisons pose 1");
    @(negedge clk);
    clear_inputs();
    #1;
    check(!overwrite_ready[1] && overwrite_ready[0],
          "poison blocks only pose 1 until reset");

    // Overflow saturates and poisons its slot; the sticky error survives later
    // valid traffic.
    reset_guard();
    accept_pose_id = 1'b0;
    accept_count = 4'd15;
    step();
    @(negedge clk);
    clear_inputs();
    accept_count = 4'd15;
    step();
    @(negedge clk);
    clear_inputs();
    accept_count = 4'd2;
    #1;
    check(!overwrite_ready[0],
          "pending overflow cannot advertise overwrite readiness");
    step();
    check(model_count0 == MAX_COUNT && model_poison0 && model_error,
          "overflow saturates and poisons pose 0");
    @(negedge clk);
    clear_inputs();
    retire_count0 = 4'd15;
    step();
    check(model_count0 == 16 && model_poison0 && model_error &&
          !overwrite_ready[0],
          "poison and accounting error remain sticky after valid retire");

    reset_guard();
    check(saw_accept0 && saw_accept1,
          "both accept pose IDs were exercised");
    check(saw_both_update,
          "simultaneous two-slot updates were exercised");
    check(saw_ready0 && saw_ready1,
          "both overwrite-ready outputs were exercised");

    $display("POSE_EPOCH_COUNT_GUARD2_SUMMARY cycles=%0d errors=%0d",
             RANDOM_CYCLES, errors);
    if (errors == 0)
      $display("POSE_EPOCH_COUNT_GUARD2_PASS");
    else
      $display("POSE_EPOCH_COUNT_GUARD2_FAIL");
    $finish;
  end
endmodule
