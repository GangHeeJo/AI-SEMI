// Atomically distribute one pose epoch of affine coefficients to a raster of
// independent sensor regions.  Each region owns its existing pose history and
// in-flight guard; this block only sequences their write ports.
//
// Configuration commands use ready/valid and must be:
//   BEGIN(target pose), ROWS*COLS ordered WRITE commands, PUBLISH(target pose).
// ABORT may cancel an incomplete load; already-written inactive records remain
// invisible and will be overwritten by the next complete load of that pose.
// A WRITE is accepted only when the addressed region reports pose_wr_ready and
// pose_wr_commit.  Until PUBLISH, active_pose_version does not change, so a
// partially loaded pose can never tag a newly accepted event.
module affine_region_pose_loader #(
  // Contract: ROWS/COLS are positive and REGION_X/Y_W represent their
  // respective maximum zero-based indices.
  parameter integer REGION_COLS = 30,
  parameter integer REGION_ROWS = 23,
  parameter integer REGION_X_W = 5,
  parameter integer REGION_Y_W = 5,
  parameter integer POSE_W = 1,
  parameter integer MATRIX_W = 16,
  parameter integer OFFSET_W = 24
) (
  input                               clk,
  input                               rst,

  input                               cfg_valid,
  output reg                          cfg_ready,
  input      [1:0]                    cfg_op,
  input      [REGION_X_W-1:0]         cfg_region_x,
  input      [REGION_Y_W-1:0]         cfg_region_y,
  input      [POSE_W-1:0]             cfg_pose_version,
  input signed [MATRIX_W-1:0]         cfg_m00,
  input signed [MATRIX_W-1:0]         cfg_m01,
  input signed [MATRIX_W-1:0]         cfg_m10,
  input signed [MATRIX_W-1:0]         cfg_m11,
  input signed [OFFSET_W-1:0]         cfg_tx,
  input signed [OFFSET_W-1:0]         cfg_ty,

  output reg                          region_wr_req,
  output     [REGION_X_W-1:0]         region_wr_x,
  output     [REGION_Y_W-1:0]         region_wr_y,
  output     [POSE_W-1:0]             region_wr_pose_version,
  output signed [MATRIX_W-1:0]        region_wr_m00,
  output signed [MATRIX_W-1:0]        region_wr_m01,
  output signed [MATRIX_W-1:0]        region_wr_m10,
  output signed [MATRIX_W-1:0]        region_wr_m11,
  output signed [OFFSET_W-1:0]        region_wr_tx,
  output signed [OFFSET_W-1:0]        region_wr_ty,
  input                               region_wr_ready,
  input                               region_wr_commit,
  input                               region_pose_accounting_error,

  output reg                          active_pose_valid,
  output reg [POSE_W-1:0]             active_pose_version,
  output                              load_busy,
  output                              awaiting_publish,
  output     [REGION_X_W-1:0]         expected_region_x,
  output     [REGION_Y_W-1:0]         expected_region_y,
  output     [POSE_W-1:0]             load_pose_version,
  output reg                          publish_pulse,
  output reg                          cfg_protocol_error
);
  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;
  localparam [1:0] CFG_ABORT = 2'd3;

  localparam [1:0] STATE_IDLE = 2'd0;
  localparam [1:0] STATE_LOAD = 2'd1;
  localparam [1:0] STATE_PUBLISH = 2'd2;
  localparam [1:0] STATE_ERROR = 2'd3;

  reg [1:0] state;
  reg [REGION_X_W-1:0] expected_x;
  reg [REGION_Y_W-1:0] expected_y;
  reg [POSE_W-1:0] loading_pose;

  wire begin_is_safe = (cfg_op == CFG_BEGIN) &&
                       (!active_pose_valid ||
                        cfg_pose_version != active_pose_version);
  wire write_is_expected = (cfg_op == CFG_WRITE) &&
                           (cfg_pose_version == loading_pose) &&
                           (cfg_region_x == expected_x) &&
                           (cfg_region_y == expected_y);
  wire publish_is_expected = (cfg_op == CFG_PUBLISH) &&
                             (cfg_pose_version == loading_pose);
  wire final_region =
    (expected_x == REGION_COLS-1) && (expected_y == REGION_ROWS-1);

  assign region_wr_x = expected_x;
  assign region_wr_y = expected_y;
  assign region_wr_pose_version = loading_pose;
  assign region_wr_m00 = cfg_m00;
  assign region_wr_m01 = cfg_m01;
  assign region_wr_m10 = cfg_m10;
  assign region_wr_m11 = cfg_m11;
  assign region_wr_tx = cfg_tx;
  assign region_wr_ty = cfg_ty;

  assign load_busy = (state == STATE_LOAD) || (state == STATE_PUBLISH);
  assign awaiting_publish = (state == STATE_PUBLISH);
  assign expected_region_x = expected_x;
  assign expected_region_y = expected_y;
  assign load_pose_version = loading_pose;

  always @(*) begin
    cfg_ready = 1'b0;
    region_wr_req = 1'b0;
    if (!rst && !cfg_protocol_error &&
        !region_pose_accounting_error) begin
      case (state)
        STATE_IDLE: cfg_ready = 1'b1;
        STATE_LOAD: begin
          if (write_is_expected) begin
            // pose_wr_req is a commit pulse, not a held ready/valid signal.
            // Gate it with ready to avoid expected busy cycles appearing as
            // pose-write rejection diagnostics in every region.
            region_wr_req = cfg_valid && region_wr_ready;
            cfg_ready = region_wr_ready;
          end else begin
            // Consume a malformed command so it deterministically fail-stops.
            cfg_ready = 1'b1;
          end
        end
        STATE_PUBLISH: cfg_ready = 1'b1;
        default: cfg_ready = 1'b0;
      endcase
    end
  end

  wire cfg_fire = cfg_valid && cfg_ready;
  wire region_contract_error = region_wr_commit &&
                               (!region_wr_req || !region_wr_ready);

  always @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      expected_x <= {REGION_X_W{1'b0}};
      expected_y <= {REGION_Y_W{1'b0}};
      loading_pose <= {POSE_W{1'b0}};
      active_pose_valid <= 1'b0;
      active_pose_version <= {POSE_W{1'b0}};
      publish_pulse <= 1'b0;
      cfg_protocol_error <= 1'b0;
    end else begin
      publish_pulse <= 1'b0;
      if (region_pose_accounting_error || region_contract_error) begin
        state <= STATE_ERROR;
        cfg_protocol_error <= 1'b1;
      end else if (!cfg_protocol_error && cfg_fire) begin
        case (state)
          STATE_IDLE: begin
            if (begin_is_safe) begin
              loading_pose <= cfg_pose_version;
              expected_x <= {REGION_X_W{1'b0}};
              expected_y <= {REGION_Y_W{1'b0}};
              state <= STATE_LOAD;
            end else begin
              state <= STATE_ERROR;
              cfg_protocol_error <= 1'b1;
            end
          end

          STATE_LOAD: begin
            if (cfg_op == CFG_ABORT) begin
              expected_x <= {REGION_X_W{1'b0}};
              expected_y <= {REGION_Y_W{1'b0}};
              state <= STATE_IDLE;
            end else if (!write_is_expected || !region_wr_commit) begin
              state <= STATE_ERROR;
              cfg_protocol_error <= 1'b1;
            end else if (final_region) begin
              state <= STATE_PUBLISH;
            end else if (expected_x == REGION_COLS-1) begin
              expected_x <= {REGION_X_W{1'b0}};
              expected_y <= expected_y + 1'b1;
            end else begin
              expected_x <= expected_x + 1'b1;
            end
          end

          STATE_PUBLISH: begin
            if (cfg_op == CFG_ABORT) begin
              expected_x <= {REGION_X_W{1'b0}};
              expected_y <= {REGION_Y_W{1'b0}};
              state <= STATE_IDLE;
            end else if (publish_is_expected) begin
              active_pose_valid <= 1'b1;
              active_pose_version <= loading_pose;
              publish_pulse <= 1'b1;
              state <= STATE_IDLE;
            end else begin
              state <= STATE_ERROR;
              cfg_protocol_error <= 1'b1;
            end
          end

          default: begin
            state <= STATE_ERROR;
            cfg_protocol_error <= 1'b1;
          end
        endcase
      end
    end
  end
endmodule
