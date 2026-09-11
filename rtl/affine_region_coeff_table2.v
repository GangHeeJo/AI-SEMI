// Central double-buffered affine coefficient table for sensor regions.
//
// The write port is directly compatible with affine_region_pose_loader.  A
// target pose bank accepts writes only while pose_overwrite_ready says that
// the whole epoch has no remaining users.  The first (and every subsequent)
// write hides that bank; a loader-validated PUBLISH exposes it atomically.
// epoch_visible is the validity bit for a complete bank.  Per-record validity
// is intentionally omitted so the coefficient array has no reset loop and can
// infer as SRAM.  This block relies on the loader's complete row-major write
// contract and deliberately does not reject an early PUBLISH by itself.
//
// Lookup is a one-outstanding synchronous ready/valid interface.  A response
// remains stable while stalled.  If a lookup and write for the same pose bank
// are accepted on one edge, the lookup returns found=0: starting an overwrite
// hides the complete old bank before any partially replaced record is visible.
// A simultaneous lookup of the other pose bank reads normally.
//
// Contract: POSE_W is 1 (two banks), REGION_COLS/ROWS are positive, and the
// supplied X/Y/region-id widths represent their respective ranges.
module affine_region_coeff_table2 #(
  parameter integer REGION_COLS = 30,
  parameter integer REGION_ROWS = 23,
  parameter integer REGION_X_W =
    (REGION_COLS < 2) ? 1 : $clog2(REGION_COLS),
  parameter integer REGION_Y_W =
    (REGION_ROWS < 2) ? 1 : $clog2(REGION_ROWS),
  parameter integer REGION_ID_W =
    (REGION_COLS*REGION_ROWS < 2) ? 1 :
    $clog2(REGION_COLS*REGION_ROWS),
  parameter integer POSE_W = 1,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24
) (
  input                               clk,
  input                               rst,

  input                               region_wr_req,
  input      [REGION_X_W-1:0]         region_wr_x,
  input      [REGION_Y_W-1:0]         region_wr_y,
  input      [POSE_W-1:0]             region_wr_pose_version,
  input signed [MATRIX_W-1:0]         region_wr_m00,
  input signed [MATRIX_W-1:0]         region_wr_m01,
  input signed [MATRIX_W-1:0]         region_wr_m10,
  input signed [MATRIX_W-1:0]         region_wr_m11,
  input signed [OFFSET_W-1:0]         region_wr_tx,
  input signed [OFFSET_W-1:0]         region_wr_ty,
  output                              region_wr_ready,
  output                              region_wr_commit,
  input      [1:0]                    pose_overwrite_ready,

  input                               publish_pulse,
  input      [POSE_W-1:0]             publish_pose_version,

  input                               lookup_valid,
  output                              lookup_ready,
  input      [POSE_W-1:0]             lookup_pose_version,
  input      [REGION_ID_W-1:0]        lookup_region_id,
  output reg                          lookup_rsp_valid,
  input                               lookup_rsp_ready,
  output reg                          lookup_rsp_found,
  output reg signed [MATRIX_W-1:0]    lookup_rsp_m00,
  output reg signed [MATRIX_W-1:0]    lookup_rsp_m01,
  output reg signed [MATRIX_W-1:0]    lookup_rsp_m10,
  output reg signed [MATRIX_W-1:0]    lookup_rsp_m11,
  output reg signed [OFFSET_W-1:0]    lookup_rsp_tx,
  output reg signed [OFFSET_W-1:0]    lookup_rsp_ty
);
  localparam integer REGION_COUNT = REGION_COLS * REGION_ROWS;
  localparam integer TABLE_DEPTH = 2 * REGION_COUNT;
  localparam integer TABLE_ADDR_W =
    (TABLE_DEPTH < 2) ? 1 : $clog2(TABLE_DEPTH);
  localparam integer COEFF_W = 4*MATRIX_W + 2*OFFSET_W;

  reg [COEFF_W-1:0] coeff_mem [0:TABLE_DEPTH-1];
  reg [1:0]         epoch_visible;

  wire wr_address_valid =
    (region_wr_x < REGION_COLS) && (region_wr_y < REGION_ROWS);
  wire [REGION_ID_W-1:0] wr_region_id =
    region_wr_y * REGION_COLS + region_wr_x;
  wire [TABLE_ADDR_W-1:0] wr_address =
    region_wr_pose_version * REGION_COUNT + wr_region_id;

  assign region_wr_ready = !rst && wr_address_valid &&
                           pose_overwrite_ready[region_wr_pose_version];
  assign region_wr_commit = region_wr_req && region_wr_ready;

  assign lookup_ready = !rst &&
                        (!lookup_rsp_valid || lookup_rsp_ready);

  wire lookup_address_valid = lookup_region_id < REGION_COUNT;
  wire [TABLE_ADDR_W-1:0] lookup_address =
    lookup_pose_version * REGION_COUNT + lookup_region_id;
  wire [TABLE_ADDR_W-1:0] lookup_safe_address =
    lookup_address_valid ? lookup_address : {TABLE_ADDR_W{1'b0}};
  wire write_targets_lookup_pose = region_wr_commit &&
    (region_wr_pose_version == lookup_pose_version);
  wire lookup_epoch_visible = epoch_visible[lookup_pose_version] ||
    (publish_pulse &&
     (publish_pose_version == lookup_pose_version));
  wire lookup_record_visible = lookup_address_valid &&
    lookup_epoch_visible && !write_targets_lookup_pose;
  wire lookup_fire = lookup_valid && lookup_ready;

  always @(posedge clk) begin
    if (rst) begin
      epoch_visible <= 2'b00;
      lookup_rsp_valid <= 1'b0;
      lookup_rsp_found <= 1'b0;
      lookup_rsp_m00 <= {MATRIX_W{1'b0}};
      lookup_rsp_m01 <= {MATRIX_W{1'b0}};
      lookup_rsp_m10 <= {MATRIX_W{1'b0}};
      lookup_rsp_m11 <= {MATRIX_W{1'b0}};
      lookup_rsp_tx <= {OFFSET_W{1'b0}};
      lookup_rsp_ty <= {OFFSET_W{1'b0}};
    end else begin
      if (region_wr_commit) begin
        coeff_mem[wr_address] <= {
          region_wr_m00, region_wr_m01, region_wr_m10, region_wr_m11,
          region_wr_tx, region_wr_ty
        };
        epoch_visible[region_wr_pose_version] <= 1'b0;
      end

      // A write to the same bank wins over an impossible same-cycle publish.
      if (publish_pulse &&
          (!region_wr_commit ||
           publish_pose_version != region_wr_pose_version))
        epoch_visible[publish_pose_version] <= 1'b1;

      if (lookup_fire) begin
        lookup_rsp_valid <= 1'b1;
        lookup_rsp_found <= lookup_record_visible;
        if (lookup_record_visible) begin
          {
            lookup_rsp_m00, lookup_rsp_m01,
            lookup_rsp_m10, lookup_rsp_m11,
            lookup_rsp_tx, lookup_rsp_ty
          } <= coeff_mem[lookup_safe_address];
        end else begin
          lookup_rsp_m00 <= {MATRIX_W{1'b0}};
          lookup_rsp_m01 <= {MATRIX_W{1'b0}};
          lookup_rsp_m10 <= {MATRIX_W{1'b0}};
          lookup_rsp_m11 <= {MATRIX_W{1'b0}};
          lookup_rsp_tx <= {OFFSET_W{1'b0}};
          lookup_rsp_ty <= {OFFSET_W{1'b0}};
        end
      end else if (lookup_rsp_valid && lookup_rsp_ready) begin
        lookup_rsp_valid <= 1'b0;
      end
    end
  end
endmodule
