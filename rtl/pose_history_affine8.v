// Small pose-version history with eight combinational read ports.
//
// The table is deliberately separate from the coordinate arithmetic.  A pose
// record must remain valid until every AER event carrying that version has
// retired.  A same-cycle write/read of the same version is write-through.
module pose_history_affine8 #(
  parameter POSE_W  = 4,
  parameter MATRIX_W = 16,
  parameter OFFSET_W = 24,
  parameter LANES   = 8
)(
  input                              clk,
  input                              rst,
  input                              pose_wr_en,
  input      [POSE_W-1:0]            pose_wr_id,
  input signed [MATRIX_W-1:0]        pose_wr_m00,
  input signed [MATRIX_W-1:0]        pose_wr_m01,
  input signed [MATRIX_W-1:0]        pose_wr_m10,
  input signed [MATRIX_W-1:0]        pose_wr_m11,
  input signed [OFFSET_W-1:0]        pose_wr_tx,
  input signed [OFFSET_W-1:0]        pose_wr_ty,
  input      [LANES*POSE_W-1:0]      pose_rd_id_flat,
  output     [LANES-1:0]             pose_rd_found,
  output     [LANES*MATRIX_W-1:0]    pose_rd_m00_flat,
  output     [LANES*MATRIX_W-1:0]    pose_rd_m01_flat,
  output     [LANES*MATRIX_W-1:0]    pose_rd_m10_flat,
  output     [LANES*MATRIX_W-1:0]    pose_rd_m11_flat,
  output     [LANES*OFFSET_W-1:0]    pose_rd_tx_flat,
  output     [LANES*OFFSET_W-1:0]    pose_rd_ty_flat
);
  localparam DEPTH = (1 << POSE_W);

  reg valid_mem [0:DEPTH-1];
  reg signed [MATRIX_W-1:0] m00_mem [0:DEPTH-1];
  reg signed [MATRIX_W-1:0] m01_mem [0:DEPTH-1];
  reg signed [MATRIX_W-1:0] m10_mem [0:DEPTH-1];
  reg signed [MATRIX_W-1:0] m11_mem [0:DEPTH-1];
  reg signed [OFFSET_W-1:0] tx_mem  [0:DEPTH-1];
  reg signed [OFFSET_W-1:0] ty_mem  [0:DEPTH-1];
  integer i;

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < DEPTH; i = i + 1)
        valid_mem[i] <= 1'b0;
    end else if (pose_wr_en) begin
      valid_mem[pose_wr_id] <= 1'b1;
      m00_mem[pose_wr_id] <= pose_wr_m00;
      m01_mem[pose_wr_id] <= pose_wr_m01;
      m10_mem[pose_wr_id] <= pose_wr_m10;
      m11_mem[pose_wr_id] <= pose_wr_m11;
      tx_mem[pose_wr_id]  <= pose_wr_tx;
      ty_mem[pose_wr_id]  <= pose_wr_ty;
    end
  end

  genvar g;
  generate
    for (g = 0; g < LANES; g = g + 1) begin: read_port
      wire [POSE_W-1:0] rd_id = pose_rd_id_flat[g*POSE_W +: POSE_W];
      wire bypass = pose_wr_en && (pose_wr_id == rd_id);

      assign pose_rd_found[g] = bypass ? 1'b1 : valid_mem[rd_id];
      assign pose_rd_m00_flat[g*MATRIX_W +: MATRIX_W] = bypass ? pose_wr_m00 : m00_mem[rd_id];
      assign pose_rd_m01_flat[g*MATRIX_W +: MATRIX_W] = bypass ? pose_wr_m01 : m01_mem[rd_id];
      assign pose_rd_m10_flat[g*MATRIX_W +: MATRIX_W] = bypass ? pose_wr_m10 : m10_mem[rd_id];
      assign pose_rd_m11_flat[g*MATRIX_W +: MATRIX_W] = bypass ? pose_wr_m11 : m11_mem[rd_id];
      assign pose_rd_tx_flat [g*OFFSET_W +: OFFSET_W] = bypass ? pose_wr_tx  : tx_mem[rd_id];
      assign pose_rd_ty_flat [g*OFFSET_W +: OFFSET_W] = bypass ? pose_wr_ty  : ty_mem[rd_id];
    end
  endgenerate
endmodule
