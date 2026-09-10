// Four-bank external-memory time surface for four ready/valid world streams.
//
// Valid in-range coordinates are striped by world_x modulo four.  Each SRAM
// therefore stores GRID_H rows of GRID_W/4 cells, with local_x=world_x/4.
// Same-cell events always meet in one writer, whose timestamp comparison makes
// the final cell state independent of cross-input service order.  Diagnostic
// pulse and write counts can still differ with service order.  Unmapped records
// are consumed without a memory access; mapped range failures are sent through
// bank zero so the existing writer supplies the range_error pulse.
module world_time_surface_sram_banked4 #(
  parameter integer GRID_W = 256,
  parameter integer GRID_H = 256,
  parameter integer COORD_W = 16,
  parameter integer TIMESTAMP_W = 32,
  parameter integer ADDR_W = (((GRID_W / 4) * GRID_H) <= 1)
                           ? 1 : $clog2((GRID_W / 4) * GRID_H)
) (
  input                              clk,
  input                              rst,

  input      [3:0]                   event_valid,
  output     [3:0]                   event_ready,
  input      [3:0]                   mapped_valid,
  input      [4*COORD_W-1:0]         world_x_flat,
  input      [4*COORD_W-1:0]         world_y_flat,
  input      [3:0]                   polarity,
  input      [4*TIMESTAMP_W-1:0]     occurrence_timestamp_flat,

  output     [3:0]                   update_applied,
  output     [3:0]                   equal_time_merged,
  output     [3:0]                   stale_ignored,
  output     [3:0]                   range_error,

  output     [3:0]                   mem_rd_req_valid,
  input      [3:0]                   mem_rd_req_ready,
  output     [4*ADDR_W-1:0]          mem_rd_req_addr_flat,

  input      [3:0]                   mem_rd_rsp_valid,
  output     [3:0]                   mem_rd_rsp_ready,
  input      [3:0]                   mem_rd_rsp_cell_valid,
  input      [4*TIMESTAMP_W-1:0]     mem_rd_rsp_timestamp_flat,
  input      [7:0]                   mem_rd_rsp_polarity_seen_flat,

  output     [3:0]                   mem_wr_req_valid,
  input      [3:0]                   mem_wr_req_ready,
  output     [4*ADDR_W-1:0]          mem_wr_req_addr_flat,
  output     [3:0]                   mem_wr_req_cell_valid,
  output     [4*TIMESTAMP_W-1:0]     mem_wr_req_timestamp_flat,
  output     [7:0]                   mem_wr_req_polarity_seen_flat
);
  localparam integer BANK_GRID_W = GRID_W / 4;
  localparam integer X_LSB = 0;
  localparam integer Y_LSB = X_LSB + COORD_W;
  localparam integer POL_LSB = Y_LSB + COORD_W;
  localparam integer TIME_LSB = POL_LSB + 1;
  localparam integer EVENT_W = TIME_LSB + TIMESTAMP_W;

  // route_* is bank-major: route index = bank*4 + input lane.
  wire [15:0] route_valid;
  wire [15:0] route_ready;
  wire [16*EVENT_W-1:0] route_data_flat;
  wire [3:0] bank_event_valid;
  wire [3:0] bank_event_ready;
  wire [4*EVENT_W-1:0] bank_event_data_flat;
  wire [7:0] unused_selected_source;

  genvar lane;
  genvar bank;
  generate
    for (bank = 0; bank < 4; bank = bank + 1) begin: route_bank
      for (lane = 0; lane < 4; lane = lane + 1) begin: route_lane
        wire signed [COORD_W-1:0] lane_world_x;
        wire signed [COORD_W-1:0] lane_world_y;
        wire signed [COORD_W-1:0] lane_local_x;
        wire lane_in_range;
        wire [1:0] lane_target_bank;

        assign lane_world_x =
          world_x_flat[lane*COORD_W +: COORD_W];
        assign lane_world_y =
          world_y_flat[lane*COORD_W +: COORD_W];
        assign lane_local_x = $signed(lane_world_x) >>> 2;
        assign lane_in_range =
          ($signed(lane_world_x) >= 0) &&
          ($signed(lane_world_x) < GRID_W) &&
          ($signed(lane_world_y) >= 0) &&
          ($signed(lane_world_y) < GRID_H);
        assign lane_target_bank = lane_in_range ? lane_world_x[1:0] : 2'd0;

        assign route_valid[bank*4 + lane] =
          event_valid[lane] && mapped_valid[lane] &&
          (lane_target_bank == bank);
        assign route_data_flat[(bank*4 + lane)*EVENT_W +: EVENT_W] = {
          occurrence_timestamp_flat[lane*TIMESTAMP_W +: TIMESTAMP_W],
          polarity[lane], lane_world_y, lane_local_x
        };
      end

      rr_stream_arbiter4 #(.DATA_W(EVENT_W)) u_arbiter (
        .clk(clk), .rst(rst),
        .in_valid(route_valid[bank*4 +: 4]),
        .in_data_flat(route_data_flat[bank*4*EVENT_W +: 4*EVENT_W]),
        .in_ready(route_ready[bank*4 +: 4]),
        .out_valid(bank_event_valid[bank]),
        .out_data(bank_event_data_flat[bank*EVENT_W +: EVENT_W]),
        .out_source(unused_selected_source[bank*2 +: 2]),
        .out_ready(bank_event_ready[bank])
      );

      world_time_surface_sram_writer #(
        .GRID_W(BANK_GRID_W), .GRID_H(GRID_H), .COORD_W(COORD_W),
        .TIMESTAMP_W(TIMESTAMP_W), .ADDR_W(ADDR_W)
      ) u_writer (
        .clk(clk), .rst(rst),
        .event_valid(bank_event_valid[bank]),
        .event_ready(bank_event_ready[bank]),
        .mapped_valid(1'b1),
        .world_x(bank_event_data_flat[bank*EVENT_W + X_LSB +: COORD_W]),
        .world_y(bank_event_data_flat[bank*EVENT_W + Y_LSB +: COORD_W]),
        .polarity(bank_event_data_flat[bank*EVENT_W + POL_LSB]),
        .occurrence_timestamp(
          bank_event_data_flat[bank*EVENT_W + TIME_LSB +: TIMESTAMP_W]),
        .update_applied(update_applied[bank]),
        .equal_time_merged(equal_time_merged[bank]),
        .stale_ignored(stale_ignored[bank]),
        .range_error(range_error[bank]),
        .mem_rd_req_valid(mem_rd_req_valid[bank]),
        .mem_rd_req_ready(mem_rd_req_ready[bank]),
        .mem_rd_req_addr(mem_rd_req_addr_flat[bank*ADDR_W +: ADDR_W]),
        .mem_rd_rsp_valid(mem_rd_rsp_valid[bank]),
        .mem_rd_rsp_ready(mem_rd_rsp_ready[bank]),
        .mem_rd_rsp_cell_valid(mem_rd_rsp_cell_valid[bank]),
        .mem_rd_rsp_timestamp(
          mem_rd_rsp_timestamp_flat[bank*TIMESTAMP_W +: TIMESTAMP_W]),
        .mem_rd_rsp_polarity_seen(
          mem_rd_rsp_polarity_seen_flat[bank*2 +: 2]),
        .mem_wr_req_valid(mem_wr_req_valid[bank]),
        .mem_wr_req_ready(mem_wr_req_ready[bank]),
        .mem_wr_req_addr(mem_wr_req_addr_flat[bank*ADDR_W +: ADDR_W]),
        .mem_wr_req_cell_valid(mem_wr_req_cell_valid[bank]),
        .mem_wr_req_timestamp(
          mem_wr_req_timestamp_flat[bank*TIMESTAMP_W +: TIMESTAMP_W]),
        .mem_wr_req_polarity_seen(
          mem_wr_req_polarity_seen_flat[bank*2 +: 2])
      );
    end

    for (lane = 0; lane < 4; lane = lane + 1) begin: input_ready_lane
      assign event_ready[lane] = !rst &&
        (!mapped_valid[lane] ||
         route_ready[lane] || route_ready[4 + lane] ||
         route_ready[8 + lane] || route_ready[12 + lane]);
    end
  endgenerate

  // Contract: GRID_W is positive and divisible by four; GRID_W and GRID_H fit
  // signed COORD_W; TIMESTAMP_W is at least two; and ADDR_W can represent every
  // address in (GRID_W/4)*GRID_H. Checks stay in verification code for
  // synthesis portability.
endmodule
