// aer_tx16_adaptive2_serial의 링크폭 스윕 실험판(W=16). 좁은 링크(4비트, §83)가
// 처리율 병목으로 cluster2보다 3.3배 나쁜 손실을 냈던 것의 원인이 "링크가 좁아서
// 사이클을 너무 많이 먹는다"였는지 직접 확인하려고 만듦. 헤더 1청크(16비트 중
// mode[1:0]+lastidx[3:0]만 사용, 나머지 미사용)+raw는 K개 주소청크(4비트를 16비트
// 청크 하위에 넣음, 상위비트 낭비 -- 패킹 최적화는 안 함, 링크폭 자체의 효과만 보려는
// 최소변경) 또는 bitmap은 마스크 전체를 단 1청크로(16비트 폭이라 통짜로 들어감).
module aer_tx16_adaptive2_serial_w16 #(
  parameter NUM_SOURCES = 16,
  parameter ADDRESS_WIDTH = 4,
  parameter LINK_WIDTH = 16
) (
  input  wire                      clk,
  input  wire                      rst,
  input  wire [NUM_SOURCES-1:0]    req,
  output reg                       link_valid,
  output reg  [LINK_WIDTH-1:0]     link_data,
  output reg  [NUM_SOURCES-1:0]    ack_mask
);
  localparam S_IDLE = 2'd0, S_HEADER = 2'd1, S_DATA = 2'd2;
  reg [1:0] state;
  reg [1:0] cap_mode;      // 00=raw, 10=bitmap
  reg [3:0] cap_lastidx;   // raw: count-1(0~15), bitmap: 항상 0(1청크)
  reg [NUM_SOURCES-1:0] cap_mask;
  reg [LINK_WIDTH-1:0] cap_chunk [0:15];
  reg [3:0] chunk_idx;
  integer i, n, k;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE; link_valid <= 1'b0; link_data <= {LINK_WIDTH{1'b0}};
      ack_mask <= {NUM_SOURCES{1'b0}};
      cap_mode <= 2'd0; cap_lastidx <= 4'd0; cap_mask <= {NUM_SOURCES{1'b0}};
      chunk_idx <= 4'd0;
    end else begin
      ack_mask <= {NUM_SOURCES{1'b0}};
      case (state)
        S_IDLE: begin
          link_valid <= 1'b0;
          if (req != {NUM_SOURCES{1'b0}}) begin
            k = 0;
            for (i = 0; i < NUM_SOURCES; i = i + 1) if (req[i]) k = k + 1;
            cap_mask <= req;
            // 헤더(1)+K개 청크(raw) vs 헤더(1)+1청크(bitmap, W=16이라 통짜)
            if ((1 + k) <= 2) begin
              cap_mode <= 2'd0;
              cap_lastidx <= (k - 1);
              n = 0;
              for (i = 0; i < NUM_SOURCES; i = i + 1)
                if (req[i] && n < NUM_SOURCES) begin
                  cap_chunk[n] <= {{(LINK_WIDTH-ADDRESS_WIDTH){1'b0}}, i[ADDRESS_WIDTH-1:0]};
                  n = n + 1;
                end
            end else begin
              cap_mode <= 2'd2;
              cap_lastidx <= 4'd0;
              cap_chunk[0] <= req;
            end
            state <= S_HEADER;
          end
        end
        S_HEADER: begin
          link_valid <= 1'b1;
          link_data <= {{(LINK_WIDTH-6){1'b0}}, cap_mode, cap_lastidx};
          chunk_idx <= 4'd0;
          state <= S_DATA;
        end
        S_DATA: begin
          link_valid <= 1'b1;
          link_data <= cap_chunk[chunk_idx];
          if (chunk_idx == cap_lastidx) begin
            ack_mask <= cap_mask;
            state <= S_IDLE;
          end else begin
            chunk_idx <= chunk_idx + 4'd1;
          end
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
