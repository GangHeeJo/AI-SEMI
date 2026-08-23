// 2단 적응형(raw list + bitmap) 스트리밍 TX -- §82의 조합논리 비트비용 모델을 진짜
// 좁은 링크(4비트+valid, 5핀)로 여러 사이클에 걸쳐 순차 전송하는 실제 시퀀서로 승격.
// 단일사이클 병렬버스(최악모드 폭에 고정)로 냈다면 "비트를 아꼈다"는 이득이 핀 폭에는
// 전혀 반영 안 됐을 것 -- 직접 만들어보며 알게 된 것. 헤더 1청크(4비트: mode[1:0]+
// lastidx[1:0]) + raw면 (lastidx+1)개 주소청크(4비트씩, lastidx=count-1) 또는 bitmap이면
// 마스크 4청크(4비트씩, lastidx 고정 3).
//
// req는 cluster2와 같은 관례: "현재 pending" 레벨 신호(admission bookkeeping은 상위
// 하네스가 함). ack_mask는 한 배치 전송이 끝나는 사이클에 1펄스, 하네스가 pending
// 클리어에 씀.
//
// EF 경로는 N=16에서 §78 실측으로 단 한 번도 선택 안 됨이 확정된 죽은 코드라 아예 안
// 넣음(YAGNI) -- N이 커지면(§79) 준영의 a6_ef_batch_encoder 페이로드 생성 로직을 헤더의
// mode=2'b01 자리에 그대로 얹으면 확장 가능하도록 mode 필드는 이미 2비트로 잡아둠.
module aer_tx16_adaptive2_serial #(
  parameter NUM_SOURCES = 16,
  parameter ADDRESS_WIDTH = 4
) (
  input  wire                      clk,
  input  wire                      rst,
  input  wire [NUM_SOURCES-1:0]    req,
  output reg                       link_valid,
  output reg  [ADDRESS_WIDTH-1:0]  link_data,
  output reg  [NUM_SOURCES-1:0]    ack_mask
);
  localparam S_IDLE = 2'd0, S_HEADER = 2'd1, S_DATA = 2'd2;
  reg [1:0] state;
  reg [1:0] cap_mode;      // 00=raw, 10=bitmap
  reg [1:0] cap_lastidx;   // 마지막 청크 인덱스(raw: count-1, bitmap: 항상 3)
  reg [NUM_SOURCES-1:0] cap_mask;
  reg [ADDRESS_WIDTH-1:0] cap_chunk [0:3];
  reg [1:0] chunk_idx;
  integer i, n, k;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE; link_valid <= 1'b0; link_data <= {ADDRESS_WIDTH{1'b0}};
      ack_mask <= {NUM_SOURCES{1'b0}};
      cap_mode <= 2'd0; cap_lastidx <= 2'd0; cap_mask <= {NUM_SOURCES{1'b0}};
      chunk_idx <= 2'd0;
    end else begin
      ack_mask <= {NUM_SOURCES{1'b0}};
      case (state)
        S_IDLE: begin
          link_valid <= 1'b0;
          if (req != {NUM_SOURCES{1'b0}}) begin
            k = 0;
            for (i = 0; i < NUM_SOURCES; i = i + 1) if (req[i]) k = k + 1;
            cap_mask <= req;
            if (k <= 4) begin
              cap_mode <= 2'd0;
              cap_lastidx <= (k - 1);
              n = 0;
              for (i = 0; i < NUM_SOURCES; i = i + 1)
                if (req[i] && n < 4) begin cap_chunk[n] <= i[ADDRESS_WIDTH-1:0]; n = n + 1; end
            end else begin
              cap_mode <= 2'd2;
              cap_lastidx <= 2'd3;
              for (n = 0; n < 4; n = n + 1)
                cap_chunk[n] <= req[n*ADDRESS_WIDTH +: ADDRESS_WIDTH];
            end
            state <= S_HEADER;
          end
        end
        S_HEADER: begin
          link_valid <= 1'b1;
          link_data <= {cap_mode, cap_lastidx};
          chunk_idx <= 2'd0;
          state <= S_DATA;
        end
        S_DATA: begin
          link_valid <= 1'b1;
          link_data <= cap_chunk[chunk_idx];
          if (chunk_idx == cap_lastidx) begin
            ack_mask <= cap_mask;
            state <= S_IDLE;
          end else begin
            chunk_idx <= chunk_idx + 2'd1;
          end
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
