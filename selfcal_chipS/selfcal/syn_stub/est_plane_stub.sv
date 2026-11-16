// TIMING-ONLY stub of est_plane for block-level Genus screening of est_core (the real plane is macro banks + valid
// flops; its ports are registered at the macro). Not for simulation or the real flow.
module est_plane #(parameter int NW = 1200, parameter int AW = 11) (
  input  logic clk, clr, we, input logic [AW-1:0] waddr, input logic [5:0] wbit, output logic busy,
  input  logic re, input logic [AW-1:0] raddr, input logic [5:0] rbit, output logic rdata);
  logic [63:0] w;
  always_ff @(posedge clk) begin
    busy <= we & ~busy;
    if (clr) w <= '0; else if (we) w[wbit] <= 1'b1;
    rdata <= re & w[rbit] & ^raddr & ^waddr;
  end
endmodule
