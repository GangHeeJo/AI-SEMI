// aer_tx16_adaptive2_serial의 짝 수신기. 헤더 청크(mode+lastidx)를 받고, 그 뒤
// (lastidx+1)개 데이터 청크를 받아 raw는 소스 인덱스로, bitmap은 니블 그대로 복원한다.
// 배치 하나가 끝나는 사이클에 decoded_valid 1펄스 + 완성된 decoded_mask를 낸다.
module aer_rx16_adaptive2_serial #(
  parameter NUM_SOURCES = 16,
  parameter ADDRESS_WIDTH = 4
) (
  input  wire                      clk,
  input  wire                      rst,
  input  wire                      link_valid,
  input  wire [ADDRESS_WIDTH-1:0]  link_data,
  output reg  [NUM_SOURCES-1:0]    decoded_mask,
  output reg                       decoded_valid
);
  localparam S_WAIT_HEADER = 1'b0, S_WAIT_DATA = 1'b1;
  reg state;
  reg [1:0] mode_r, lastidx_r, idx_r;
  reg [NUM_SOURCES-1:0] acc_mask;
  reg [NUM_SOURCES-1:0] chunk_bits;

  always @(*) begin
    chunk_bits = {NUM_SOURCES{1'b0}};
    if (mode_r == 2'd0) chunk_bits[link_data] = 1'b1;
    else chunk_bits[idx_r*ADDRESS_WIDTH +: ADDRESS_WIDTH] = link_data;
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_WAIT_HEADER; decoded_mask <= {NUM_SOURCES{1'b0}}; decoded_valid <= 1'b0;
      acc_mask <= {NUM_SOURCES{1'b0}}; idx_r <= 2'd0; mode_r <= 2'd0; lastidx_r <= 2'd0;
    end else begin
      decoded_valid <= 1'b0;
      if (link_valid) begin
        case (state)
          S_WAIT_HEADER: begin
            mode_r <= link_data[3:2];
            lastidx_r <= link_data[1:0];
            acc_mask <= {NUM_SOURCES{1'b0}};
            idx_r <= 2'd0;
            state <= S_WAIT_DATA;
          end
          S_WAIT_DATA: begin
            if (idx_r == lastidx_r) begin
              decoded_mask <= acc_mask | chunk_bits;
              decoded_valid <= 1'b1;
              state <= S_WAIT_HEADER;
            end else begin
              acc_mask <= acc_mask | chunk_bits;
              idx_r <= idx_r + 2'd1;
              state <= S_WAIT_DATA;
            end
          end
          default: state <= S_WAIT_HEADER;
        endcase
      end
    end
  end
endmodule
