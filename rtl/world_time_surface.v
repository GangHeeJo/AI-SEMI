// One-event-per-cycle reference-grid time surface.
//
// A cell stores the greatest occurrence timestamp seen for that coordinate and
// two polarity bits for events tied at that timestamp.  OR-merging equal-time
// polarity makes same-cell collisions deterministic even if AER arbitration
// changes their retirement order.  Timestamp comparison is ordinary unsigned
// comparison; the producer must reset/start a new map epoch before wrap.
//
// This small synthesizable array is a functional reference.  Large maps should
// replace the storage with an SRAM/BRAM macro while keeping this update rule.
module world_time_surface #(
  parameter integer GRID_W = 8,
  parameter integer GRID_H = 8,
  parameter integer COORD_W = 16,
  parameter integer TIMESTAMP_W = 32
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

  input      [$clog2(GRID_W)-1:0]    read_x,
  input      [$clog2(GRID_H)-1:0]    read_y,
  output                             read_valid,
  output     [TIMESTAMP_W-1:0]       read_timestamp,
  output     [1:0]                   read_polarity_seen
);
  localparam integer CELLS = GRID_W * GRID_H;

  reg valid_mem [0:CELLS-1];
  reg [TIMESTAMP_W-1:0] timestamp_mem [0:CELLS-1];
  reg [1:0] polarity_mem [0:CELLS-1];

  integer reset_i;
  integer write_addr;
  wire coordinate_in_range =
    ($signed(world_x) >= 0) && ($signed(world_x) < GRID_W) &&
    ($signed(world_y) >= 0) && ($signed(world_y) < GRID_H);
  wire accept = event_valid && event_ready;
  wire [1:0] incoming_polarity = polarity ? 2'b10 : 2'b01;

  wire [$clog2(CELLS)-1:0] read_addr = read_y * GRID_W + read_x;
  assign event_ready = ~rst;
  assign read_valid = valid_mem[read_addr];
  assign read_timestamp = read_valid
                        ? timestamp_mem[read_addr] : {TIMESTAMP_W{1'b0}};
  assign read_polarity_seen = read_valid ? polarity_mem[read_addr] : 2'b00;

  initial begin
    if (GRID_W < 2 || GRID_H < 2 || COORD_W < 2 || TIMESTAMP_W < 1)
      $fatal(1, "world_time_surface requires GRID_W/H >= 2 and positive widths");
  end

  always @(posedge clk) begin
    if (rst) begin
      update_applied <= 1'b0;
      equal_time_merged <= 1'b0;
      stale_ignored <= 1'b0;
      range_error <= 1'b0;
      for (reset_i = 0; reset_i < CELLS; reset_i = reset_i + 1) begin
        valid_mem[reset_i] <= 1'b0;
        timestamp_mem[reset_i] <= {TIMESTAMP_W{1'b0}};
        polarity_mem[reset_i] <= 2'b00;
      end
    end else begin
      update_applied <= 1'b0;
      equal_time_merged <= 1'b0;
      stale_ignored <= 1'b0;
      range_error <= 1'b0;

      if (accept && mapped_valid) begin
        if (!coordinate_in_range) begin
          range_error <= 1'b1;
        end else begin
          write_addr = $unsigned(world_y) * GRID_W + $unsigned(world_x);
          if (!valid_mem[write_addr] ||
              occurrence_timestamp > timestamp_mem[write_addr]) begin
            valid_mem[write_addr] <= 1'b1;
            timestamp_mem[write_addr] <= occurrence_timestamp;
            polarity_mem[write_addr] <= incoming_polarity;
            update_applied <= 1'b1;
          end else if (occurrence_timestamp == timestamp_mem[write_addr]) begin
            polarity_mem[write_addr] <=
              polarity_mem[write_addr] | incoming_polarity;
            update_applied <= 1'b1;
            equal_time_merged <= 1'b1;
          end else begin
            stale_ignored <= 1'b1;
          end
        end
      end
    end
  end
endmodule
