// Directed test for the "full+grant same-cycle admission" optimization.
// Force one source's FIFO to depth=2 with [front=0, back=1] via hierarchical reference
// (avoids depending on arbiter timing to reach that state), then arrive a new event
// (polarity 0) for that same source on the very cycle it gets granted. Expect: this
// grant transmits the old front (0), overrun stays 0 (bypass accepts the new arrival
// into the freed slot), and subsequent grants for that source emit 1 then 0.
//
// Timing notes (verified against arbiter2/arbiter4_tree, both purely combinational
// grant from req plus one registered "last winner" bit -- no extra clock lag there):
//   - overrun is a continuous (combinational) output -- must be sampled BEFORE the
//     clock edge that consumes this cycle's arrival/pending state (same bug class
//     fixed twice already today in the v1 testbenches).
//   - valid0/row0/col_mask0/pol_mask0 are registered -- must be read AFTER the edge
//     that follows the state we want reflected.
`timescale 1ns/1ps
module tb_steal_buf_polarity_v2_directed;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  wire [15:0] ov;
  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_v2 dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer errors;
  localparam SRC = 4; // row1 col0 -- center lane, no competing request so it always wins

  task automatic check(input cond, input [255:0] msg);
    begin
      if (!cond) begin errors = errors + 1; $display("FAIL: %0s", msg); end
      else $display("ok: %0s", msg);
    end
  endtask

  initial begin
    errors = 0;
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    @(posedge clk); #1; rst = 0;
    @(posedge clk); #1;

    // Force depth=2, [front=0, back=1] for SRC.
    dut.pending_cnt[SRC] = 2'd2;
    dut.pol_fifo0[SRC] = 1'b0;
    dut.pol_fifo1[SRC] = 1'b1;

    // Same cycle: new arrival, polarity 0, for the same (now full) source.
    arrival = 16'd0; arrival[SRC] = 1'b1;
    polarity_in = 16'd0; polarity_in[SRC] = 1'b0;
    #1; // let combinational overrun settle against the forced pending state
    check(ov[SRC] === 1'b0, "bypass: no overrun even though FIFO was full");

    @(posedge clk); #1;
    arrival = 16'd0; polarity_in = 16'd0;
    // This edge's registered outputs reflect the grant decision made against the
    // forced depth=2 state (before this edge).
    check(v0 === 1'b1 && r0 === 2'd1 && cm0[0] === 1'b1, "grant#1 targets SRC (row1 col0)");
    check(pm0[0] === 1'b0, "grant#1 carries old front polarity (0)");

    @(posedge clk); #1;
    // depth stayed at 2 (one out, one in), so SRC is granted again; front is now the
    // old back (1).
    check(v0 === 1'b1 && r0 === 2'd1 && cm0[0] === 1'b1, "grant#2 still targets SRC (depth held at 2)");
    check(pm0[0] === 1'b1, "grant#2 carries old back polarity (1)");

    @(posedge clk); #1;
    // depth 1 -> 0, front is the newly-accepted arrival (0).
    check(v0 === 1'b1 && r0 === 2'd1 && cm0[0] === 1'b1, "grant#3 targets SRC (last item)");
    check(pm0[0] === 1'b0, "grant#3 carries the bypass-accepted arrival's polarity (0)");

    @(posedge clk); #1;
    check(v0 === 1'b0, "SRC now empty, lane0 idle");

    if (errors == 0) $display("STEAL_BUF_POLARITY_V2_DIRECTED_PASS");
    else $display("STEAL_BUF_POLARITY_V2_DIRECTED_FAIL errors=%0d", errors);
    $finish;
  end
endmodule
