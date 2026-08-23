// aer_tx16_adaptive2_serial_w16의 짝 수신기.
module aer_rx16_adaptive2_serial_w16 #(
  parameter NUM_SOURCES = 16,
  parameter ADDRESS_WIDTH = 4,
  parameter LINK_WIDTH = 16
) (
  input  wire                      clk,
  input  wire                      rst,
  input  wire                      link_valid,
  input  wire [LINK_WIDTH-1:0]     link_data,
  output reg  [NUM_SOURCES-1:0]    decoded_mask,
  output reg                       decoded_valid
);
  localparam S_WAIT_HEADER = 1'b0, S_WAIT_DATA = 1'b1;
  reg state;
  reg [1:0] mode_r;
  reg [3:0] lastidx_r, idx_r;
  reg [NUM_SOURCES-1:0] acc_mask;
  reg [NUM_SOURCES-1:0] chunk_bits;

  always @(*) begin
    chunk_bits = {NUM_SOURCES{1'b0}};
    if (mode_r == 2'd0) chunk_bits[link_data[ADDRESS_WIDTH-1:0]] = 1'b1;
    else chunk_bits = link_data[NUM_SOURCES-1:0];
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_WAIT_HEADER; decoded_mask <= {NUM_SOURCES{1'b0}}; decoded_valid <= 1'b0;
      acc_mask <= {NUM_SOURCES{1'b0}}; idx_r <= 4'd0; mode_r <= 2'd0; lastidx_r <= 4'd0;
    end else begin
      decoded_valid <= 1'b0;
      if (link_valid) begin
        case (state)
          S_WAIT_HEADER: begin
            mode_r <= link_data[5:4];
            lastidx_r <= link_data[3:0];
            acc_mask <= {NUM_SOURCES{1'b0}};
            idx_r <= 4'd0;
            state <= S_WAIT_DATA;
          end
          S_WAIT_DATA: begin
            if (idx_r == lastidx_r) begin
              decoded_mask <= acc_mask | chunk_bits;
              decoded_valid <= 1'b1;
              state <= S_WAIT_HEADER;
            end else begin
              acc_mask <= acc_mask | chunk_bits;
              idx_r <= idx_r + 4'd1;
              state <= S_WAIT_DATA;
            end
          end
          default: state <= S_WAIT_HEADER;
        endcase
      end
    end
  end
endmodule
