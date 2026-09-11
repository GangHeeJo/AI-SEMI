// Track references to two alternating pose epochs.
//
// Counts are applied atomically once per cycle:
//   next = current + accepts_for_this_pose - retires_for_this_pose
// A malformed delta saturates the visible counter and permanently poisons only
// that pose slot.  A poisoned slot cannot be overwritten until reset because
// the true reference count is no longer known.
//
// The defaults cover a one-cycle accept delta of all 240x180 sensor pixels
// (43,200 < 2^16).  An integrating wrapper must still derive DELTA_W from its
// maximum accepts per cycle and COUNT_W from the total references that can be
// resident in source-pending state plus every downstream FIFO.
module pose_epoch_count_guard2 #(
  parameter integer COUNT_W = 18,
  parameter integer DELTA_W = 16
) (
  input                       clk,
  input                       rst,
  input                       accept_pose_id,
  input      [DELTA_W-1:0]    accept_count,
  input      [DELTA_W-1:0]    retire_count0,
  input      [DELTA_W-1:0]    retire_count1,
  output reg [COUNT_W-1:0]    outstanding0,
  output reg [COUNT_W-1:0]    outstanding1,
  output     [1:0]            idle,
  output     [1:0]            overwrite_ready,
  output reg                  accounting_error
);
  localparam integer MATH_W =
    ((COUNT_W > DELTA_W) ? COUNT_W : DELTA_W) + 1;
  localparam [COUNT_W-1:0] MAX_COUNT = {COUNT_W{1'b1}};

  reg [1:0] poisoned;

  wire [DELTA_W-1:0] accept_for0 = accept_pose_id
    ? {DELTA_W{1'b0}} : accept_count;
  wire [DELTA_W-1:0] accept_for1 = accept_pose_id
    ? accept_count : {DELTA_W{1'b0}};

  wire [MATH_W-1:0] count0_ext =
    {{(MATH_W-COUNT_W){1'b0}}, outstanding0};
  wire [MATH_W-1:0] count1_ext =
    {{(MATH_W-COUNT_W){1'b0}}, outstanding1};
  wire [MATH_W-1:0] accept0_ext =
    {{(MATH_W-DELTA_W){1'b0}}, accept_for0};
  wire [MATH_W-1:0] accept1_ext =
    {{(MATH_W-DELTA_W){1'b0}}, accept_for1};
  wire [MATH_W-1:0] retire0_ext =
    {{(MATH_W-DELTA_W){1'b0}}, retire_count0};
  wire [MATH_W-1:0] retire1_ext =
    {{(MATH_W-DELTA_W){1'b0}}, retire_count1};
  wire [MATH_W-1:0] max_count_ext =
    {{(MATH_W-COUNT_W){1'b0}}, MAX_COUNT};

  wire [MATH_W-1:0] before_retire0 = count0_ext + accept0_ext;
  wire [MATH_W-1:0] before_retire1 = count1_ext + accept1_ext;
  wire underflow0 = before_retire0 < retire0_ext;
  wire underflow1 = before_retire1 < retire1_ext;
  wire [MATH_W-1:0] next_count0 = before_retire0 - retire0_ext;
  wire [MATH_W-1:0] next_count1 = before_retire1 - retire1_ext;
  wire overflow0 = !underflow0 && (next_count0 > max_count_ext);
  wire overflow1 = !underflow1 && (next_count1 > max_count_ext);
  wire count_error0 = underflow0 || overflow0;
  wire count_error1 = underflow1 || overflow1;

  assign idle[0] = (outstanding0 == {COUNT_W{1'b0}});
  assign idle[1] = (outstanding1 == {COUNT_W{1'b0}});

  // A same-edge accept must not race an overwrite of the selected slot.  A
  // last retire similarly leaves ready low for that edge because idle reflects
  // the registered count; ready rises in the following cycle.
  assign overwrite_ready[0] = !rst && idle[0] && !poisoned[0] &&
                              (accept_for0 == {DELTA_W{1'b0}}) &&
                              !count_error0;
  assign overwrite_ready[1] = !rst && idle[1] && !poisoned[1] &&
                              (accept_for1 == {DELTA_W{1'b0}}) &&
                              !count_error1;

  always @(posedge clk) begin
    if (rst) begin
      outstanding0 <= {COUNT_W{1'b0}};
      outstanding1 <= {COUNT_W{1'b0}};
      poisoned <= 2'b00;
      accounting_error <= 1'b0;
    end else begin
      if (underflow0)
        outstanding0 <= {COUNT_W{1'b0}};
      else if (overflow0)
        outstanding0 <= MAX_COUNT;
      else
        outstanding0 <= next_count0[COUNT_W-1:0];

      if (underflow1)
        outstanding1 <= {COUNT_W{1'b0}};
      else if (overflow1)
        outstanding1 <= MAX_COUNT;
      else
        outstanding1 <= next_count1[COUNT_W-1:0];

      poisoned[0] <= poisoned[0] || count_error0;
      poisoned[1] <= poisoned[1] || count_error1;
      accounting_error <= accounting_error || count_error0 || count_error1;
    end
  end
endmodule
