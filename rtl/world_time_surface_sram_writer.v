// Serialized time-surface updater for an external SRAM/BRAM controller.
//
// The external memory stores {valid, timestamp, polarity_seen}. This block
// accepts one event, issues one read, compares the stored timestamp, and issues
// a write only for a newer or equal-time event. Timestamp ordering is modulo
// the counter width and is unambiguous while compared events differ by less
// than half the timestamp range; an exact half-range difference is stale.
// There is deliberately only one
// outstanding event: with zero stalls, an updating event takes a read-request,
// read-response, and write-request cycle before the next event can be accepted.
// Large-map storage and initialization therefore stay outside resettable FFs.
module world_time_surface_sram_writer #(
  parameter integer GRID_W = 256,
  parameter integer GRID_H = 256,
  parameter integer COORD_W = 16,
  parameter integer TIMESTAMP_W = 32,
  parameter integer ADDR_W = ((GRID_W * GRID_H) <= 1)
                           ? 1 : $clog2(GRID_W * GRID_H)
) (
  input                              clk,
  input                              rst,

  input                              event_valid,
  output                             event_ready,
  input                              mapped_valid,
  input signed [COORD_W-1:0]         world_x,
  input signed [COORD_W-1:0]         world_y,
  input                              polarity,
  input      [TIMESTAMP_W-1:0]       occurrence_timestamp,

  output reg                         update_applied,
  output reg                         equal_time_merged,
  output reg                         stale_ignored,
  output reg                         range_error,

  output                             mem_rd_req_valid,
  input                              mem_rd_req_ready,
  output     [ADDR_W-1:0]            mem_rd_req_addr,

  input                              mem_rd_rsp_valid,
  output                             mem_rd_rsp_ready,
  input                              mem_rd_rsp_cell_valid,
  input      [TIMESTAMP_W-1:0]       mem_rd_rsp_timestamp,
  input      [1:0]                   mem_rd_rsp_polarity_seen,

  output                             mem_wr_req_valid,
  input                              mem_wr_req_ready,
  output     [ADDR_W-1:0]            mem_wr_req_addr,
  output                             mem_wr_req_cell_valid,
  output     [TIMESTAMP_W-1:0]       mem_wr_req_timestamp,
  output     [1:0]                   mem_wr_req_polarity_seen
);
  localparam [1:0] IDLE = 2'd0;
  localparam [1:0] READ_REQUEST = 2'd1;
  localparam [1:0] READ_RESPONSE = 2'd2;
  localparam [1:0] WRITE_REQUEST = 2'd3;

  reg [1:0] state;
  reg [ADDR_W-1:0] pending_addr;
  reg pending_polarity;
  reg [TIMESTAMP_W-1:0] pending_timestamp;
  reg [TIMESTAMP_W-1:0] pending_write_timestamp;
  reg [1:0] pending_write_polarity;
  reg pending_equal;

  wire coordinate_in_range =
    ($signed(world_x) >= 0) && ($signed(world_x) < GRID_W) &&
    ($signed(world_y) >= 0) && ($signed(world_y) < GRID_H);
  wire [1:0] incoming_polarity = pending_polarity ? 2'b10 : 2'b01;
  wire [TIMESTAMP_W-1:0] timestamp_delta =
    pending_timestamp - mem_rd_rsp_timestamp;
  wire timestamp_is_newer =
    (timestamp_delta != {TIMESTAMP_W{1'b0}}) &&
    !timestamp_delta[TIMESTAMP_W-1];

  assign event_ready = !rst && (state == IDLE);
  assign mem_rd_req_valid = !rst && (state == READ_REQUEST);
  assign mem_rd_req_addr = pending_addr;
  assign mem_rd_rsp_ready = !rst && (state == READ_RESPONSE);
  assign mem_wr_req_valid = !rst && (state == WRITE_REQUEST);
  assign mem_wr_req_addr = pending_addr;
  assign mem_wr_req_cell_valid = 1'b1;
  assign mem_wr_req_timestamp = pending_write_timestamp;
  assign mem_wr_req_polarity_seen = pending_write_polarity;

  // Contract: grid dimensions and ADDR_W are positive; COORD_W and
  // TIMESTAMP_W are at least 2. Checks stay in verification code for
  // synthesis portability.
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      pending_addr <= 0;
      pending_polarity <= 1'b0;
      pending_timestamp <= 0;
      pending_write_timestamp <= 0;
      pending_write_polarity <= 2'b00;
      pending_equal <= 1'b0;
      update_applied <= 1'b0;
      equal_time_merged <= 1'b0;
      stale_ignored <= 1'b0;
      range_error <= 1'b0;
    end else begin
      update_applied <= 1'b0;
      equal_time_merged <= 1'b0;
      stale_ignored <= 1'b0;
      range_error <= 1'b0;

      case (state)
        IDLE: begin
          if (event_valid) begin
            if (!mapped_valid) begin
              // A mapping failure is consumed without touching memory.
              state <= IDLE;
            end else if (!coordinate_in_range) begin
              range_error <= 1'b1;
              state <= IDLE;
            end else begin
              pending_addr <= $unsigned(world_y) * GRID_W +
                              $unsigned(world_x);
              pending_polarity <= polarity;
              pending_timestamp <= occurrence_timestamp;
              state <= READ_REQUEST;
            end
          end
        end

        READ_REQUEST: begin
          if (mem_rd_req_ready)
            state <= READ_RESPONSE;
        end

        READ_RESPONSE: begin
          if (mem_rd_rsp_valid) begin
            if (!mem_rd_rsp_cell_valid || timestamp_is_newer) begin
              pending_write_timestamp <= pending_timestamp;
              pending_write_polarity <= incoming_polarity;
              pending_equal <= 1'b0;
              state <= WRITE_REQUEST;
            end else if (pending_timestamp == mem_rd_rsp_timestamp) begin
              pending_write_timestamp <= mem_rd_rsp_timestamp;
              pending_write_polarity <= mem_rd_rsp_polarity_seen |
                                        incoming_polarity;
              pending_equal <= 1'b1;
              state <= WRITE_REQUEST;
            end else begin
              stale_ignored <= 1'b1;
              pending_equal <= 1'b0;
              state <= IDLE;
            end
          end
        end

        WRITE_REQUEST: begin
          if (mem_wr_req_ready) begin
            update_applied <= 1'b1;
            equal_time_merged <= pending_equal;
            pending_equal <= 1'b0;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
