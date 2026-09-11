`timescale 1ns/1ps

// Default-parameter smoke for the 240x180 sensor's final 8x4 region.
// The nonexistent lower four rows are an integration tie-off, not pixels.
module tb_aer_region8x8_event_stream_edge;
  reg clk = 1'b0;
  reg rst;
  reg [63:0] arrival;
  reg [63:0] polarity_in;
  reg occurrence_pose_version;
  reg [34:0] occurrence_timestamp;
  wire [63:0] aer_overrun;
  wire [31:0] tile_fifo_overflow;
  wire [6:0] admitted_count;
  wire [5:0] drop_count0;
  wire [5:0] drop_count1;
  wire event_valid;
  wire [7:0] sensor_x;
  wire [7:0] sensor_y;
  wire polarity;
  wire pose_version;
  wire [34:0] timestamp_out;

  integer errors;
  integer outputs;
  integer cycles;
  reg [3:0] seen;

  aer_region8x8_event_stream dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in),
    .occurrence_pose_version(occurrence_pose_version),
    .occurrence_timestamp(occurrence_timestamp),
    .base_sensor_origin_x(8'd232),
    .base_sensor_origin_y(8'd176),
    .aer_overrun(aer_overrun),
    .tile_fifo_overflow(tile_fifo_overflow),
    .admitted_count(admitted_count),
    .drop_count0(drop_count0), .drop_count1(drop_count1),
    .event_valid(event_valid), .event_ready(1'b1),
    .sensor_x(sensor_x), .sensor_y(sensor_y),
    .polarity(polarity), .pose_version(pose_version),
    .occurrence_timestamp_out(timestamp_out)
  );

  always #5 clk = ~clk;

  task fail;
    input [8*96-1:0] message;
    begin
      errors = errors + 1;
      $display("CHECK_FAIL %0s", message);
    end
  endtask

  always @(posedge clk) begin
    if (!rst && event_valid) begin
      outputs = outputs + 1;
      if (sensor_y >= 180 || sensor_x >= 240)
        fail("bottom-edge tie-off emitted a nonexistent pixel");
      if (!pose_version || timestamp_out != 35'd1234)
        fail("edge event pose/timestamp changed");
      case ({sensor_y, sensor_x})
        {8'd176, 8'd232}: begin
          if (seen[0]) fail("duplicate edge pixel 0");
          seen[0] = 1'b1;
          if (polarity != 1'b0) fail("edge pixel 0 polarity");
        end
        {8'd179, 8'd235}: begin
          if (seen[1]) fail("duplicate edge pixel 1");
          seen[1] = 1'b1;
          if (polarity != 1'b1) fail("edge pixel 1 polarity");
        end
        {8'd176, 8'd236}: begin
          if (seen[2]) fail("duplicate edge pixel 2");
          seen[2] = 1'b1;
          if (polarity != 1'b1) fail("edge pixel 2 polarity");
        end
        {8'd179, 8'd239}: begin
          if (seen[3]) fail("duplicate edge pixel 3");
          seen[3] = 1'b1;
          if (polarity != 1'b0) fail("edge pixel 3 polarity");
        end
        default: fail("unexpected edge pixel");
      endcase
    end
  end

  initial begin
    rst = 1'b1;
    arrival = 64'd0;
    polarity_in = 64'd0;
    occurrence_pose_version = 1'b1;
    occurrence_timestamp = 35'd1234;
    errors = 0;
    outputs = 0;
    cycles = 0;
    seen = 4'b0000;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    // Only top-left/top-right leaves physically exist in the final 8x4 row.
    arrival = (64'd1 << 0) | (64'd1 << 15) |
              (64'd1 << 16) | (64'd1 << 31);
    polarity_in = (64'd1 << 15) | (64'd1 << 16);
    #1;
    if (admitted_count != 7'd4)
      fail("edge admission count is not four");
    @(posedge clk);
    @(negedge clk);
    arrival = 64'd0;
    polarity_in = 64'd0;

    while (outputs < 4 && cycles < 80) begin
      @(posedge clk);
      #1;
      cycles = cycles + 1;
    end
    repeat (4) @(posedge clk);
    #1;
    if (outputs != 4 || seen != 4'b1111)
      fail("edge events did not drain exactly once");
    if (aer_overrun != 0 || tile_fifo_overflow != 0 ||
        drop_count0 != 0 || drop_count1 != 0)
      fail("edge smoke unexpectedly dropped an event");

    if (errors == 0) begin
      $display("AER_REGION8X8_EDGE_PASS events=%0d", outputs);
      $finish;
    end else begin
      $fatal(1, "AER_REGION8X8_EDGE_FAIL errors=%0d", errors);
    end
  end

  initial begin
    #100000;
    $fatal(1, "AER_REGION8X8_EDGE_TIMEOUT");
  end
endmodule
