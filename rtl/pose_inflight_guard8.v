// Prevent pose-history entries from being overwritten while accepted events
// still reference them.  Write permission intentionally depends on the count at
// the start of the cycle:
//   - count==0 plus a same-cycle first accept: write commits.
//   - count==1 plus a same-cycle last retire: write rejects until next cycle.
// If an invalid configuration or protocol violation over/underflows a counter,
// that pose ID is poisoned until reset.  Saturating the visible count alone is
// not sufficient: after it drains, an unknown number of references may remain,
// so fail-safe overwrite blocking is required.
module pose_inflight_guard8 #(
  parameter integer POSE_W = 4,
  parameter integer COUNT_W = 8,
  parameter integer RETIRE_LANES = 8,
  parameter integer ACCEPT_SOURCES = 16
) (
  input                                      clk,
  input                                      rst,
  input      [ACCEPT_SOURCES-1:0]            accepted_mask,
  input      [POSE_W-1:0]                    accepted_pose_version,
  input      [RETIRE_LANES-1:0]              retire_valid,
  input      [(RETIRE_LANES*POSE_W)-1:0]     retire_pose_version_flat,
  input                                      pose_wr_req,
  input      [POSE_W-1:0]                    pose_wr_id,
  output                                     pose_wr_ready,
  output                                     pose_wr_commit,
  output                                     pose_wr_rejected,
  output reg                                 accounting_error
);
  localparam integer POSE_IDS = (1 << POSE_W);
  localparam integer ACCEPT_COUNT_W = (ACCEPT_SOURCES < 2)
    ? 1 : $clog2(ACCEPT_SOURCES + 1);
  localparam integer RETIRE_COUNT_W = (RETIRE_LANES < 2) ? 1 : $clog2(RETIRE_LANES + 1);
  localparam integer COUNT_OR_ACCEPT_W = (COUNT_W > ACCEPT_COUNT_W)
    ? COUNT_W : ACCEPT_COUNT_W;
  localparam integer BASE_MATH_W = (COUNT_OR_ACCEPT_W > RETIRE_COUNT_W)
    ? COUNT_OR_ACCEPT_W : RETIRE_COUNT_W;
  localparam integer MATH_W = BASE_MATH_W + 2;
  localparam [COUNT_W-1:0] MAX_COUNT = {COUNT_W{1'b1}};

  reg [COUNT_W-1:0] outstanding [0:POSE_IDS-1];
  reg poisoned [0:POSE_IDS-1];

  function [ACCEPT_COUNT_W-1:0] popcount_accepted;
    input [ACCEPT_SOURCES-1:0] bits;
    integer bit_idx;
    begin
      popcount_accepted = 0;
      for (bit_idx = 0; bit_idx < ACCEPT_SOURCES; bit_idx = bit_idx + 1)
        popcount_accepted = popcount_accepted + bits[bit_idx];
    end
  endfunction

  function [RETIRE_COUNT_W-1:0] retire_count_for_id;
    input [POSE_W-1:0] id;
    input [RETIRE_LANES-1:0] valids;
    input [(RETIRE_LANES*POSE_W)-1:0] ids_flat;
    integer lane_idx;
    begin
      retire_count_for_id = 0;
      for (lane_idx = 0; lane_idx < RETIRE_LANES; lane_idx = lane_idx + 1)
        if (valids[lane_idx] &&
            ids_flat[(lane_idx*POSE_W) +: POSE_W] == id)
          retire_count_for_id = retire_count_for_id + 1'b1;
    end
  endfunction

  wire [ACCEPT_COUNT_W-1:0] accepted_count = popcount_accepted(accepted_mask);
  wire pose_wr_busy = (outstanding[pose_wr_id] != {COUNT_W{1'b0}}) |
                      poisoned[pose_wr_id];
  assign pose_wr_ready = ~rst & ~pose_wr_busy;
  assign pose_wr_commit = pose_wr_req & pose_wr_ready;
  assign pose_wr_rejected = pose_wr_req & ~rst & pose_wr_busy;

  wire [POSE_IDS-1:0] count_error;
  genvar pose_id;
  generate
    for (pose_id = 0; pose_id < POSE_IDS; pose_id = pose_id + 1) begin: per_pose
      localparam [POSE_W-1:0] THIS_ID = pose_id;
      wire [ACCEPT_COUNT_W-1:0] accept_for_id =
        (accepted_pose_version == THIS_ID) ? accepted_count : 0;
      wire [RETIRE_COUNT_W-1:0] retire_for_id = retire_count_for_id(
        THIS_ID, retire_valid, retire_pose_version_flat);
      wire signed [MATH_W-1:0] current_ext = $signed(
        {{(MATH_W-COUNT_W){1'b0}}, outstanding[pose_id]});
      wire signed [MATH_W-1:0] accept_ext = $signed(
        {{(MATH_W-ACCEPT_COUNT_W){1'b0}}, accept_for_id});
      wire signed [MATH_W-1:0] retire_ext = $signed(
        {{(MATH_W-RETIRE_COUNT_W){1'b0}}, retire_for_id});
      wire signed [MATH_W-1:0] max_ext = $signed(
        {{(MATH_W-COUNT_W){1'b0}}, MAX_COUNT});
      wire signed [MATH_W-1:0] next_count = current_ext + accept_ext - retire_ext;
      wire underflow = (next_count < 0);
      wire overflow = (next_count > max_ext);

      assign count_error[pose_id] = underflow | overflow;

      always @(posedge clk) begin
        if (rst) begin
          outstanding[pose_id] <= 0;
          poisoned[pose_id] <= 1'b0;
        end else if (underflow) begin
          outstanding[pose_id] <= 0;
          poisoned[pose_id] <= 1'b1;
        end else if (overflow) begin
          outstanding[pose_id] <= MAX_COUNT;
          poisoned[pose_id] <= 1'b1;
        end else begin
          outstanding[pose_id] <= next_count[COUNT_W-1:0];
        end
      end
    end
  endgenerate

  always @(posedge clk) begin
    if (rst)
      accounting_error <= 1'b0;
    else if (|count_error)
      accounting_error <= 1'b1;
  end
endmodule
