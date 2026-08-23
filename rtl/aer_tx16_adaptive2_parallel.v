// 링크폭 스윕의 마지막 지점: 직렬화를 아예 없앤 단일사이클 병렬 버전(§82의 조합논리
// 모델을 cluster2와 동일한 관례(등록출력, 1사이클 지연)로 그대로 승격한 것). 매
// 사이클 pending 전체를 조합논리로 인코딩해 그대로 레지스터에 태움 -- raw/bitmap
// 스위칭이 사이클 수를 전혀 안 먹으므로 §83/W16에서 본 "배치당 최소 2사이클" 병목이
// 원천적으로 없음. 대신 폭이 18비트(mode 2 + payload 16) 필요 -- cluster2(14핀)보다
// 넓음. "링크를 넓히면 처리율은 개선되지만 핀 이득이 사라진다"(§83 결론)의 극단.
module aer_tx16_adaptive2_parallel #(
  parameter NUM_SOURCES = 16,
  parameter ADDRESS_WIDTH = 4
) (
  input  wire                      clk,
  input  wire                      rst,
  input  wire [NUM_SOURCES-1:0]    req,
  output reg  [1:0]                mode,     // 00=raw, 10=bitmap
  output reg  [NUM_SOURCES-1:0]    payload,  // raw: 4개 슬롯*4비트 팩, bitmap: 마스크 그대로
  output reg                       valid,
  output reg  [NUM_SOURCES-1:0]    ack_mask  // = 이번 사이클에 낸 payload가 담은 소스 전체
);
  integer i, n, k;
  reg [1:0] mode_c;
  reg [NUM_SOURCES-1:0] payload_c;
  reg valid_c;

  always @(*) begin
    k = 0;
    for (i = 0; i < NUM_SOURCES; i = i + 1) if (req[i]) k = k + 1;
    valid_c = (k != 0);
    payload_c = {NUM_SOURCES{1'b0}};
    if (!valid_c) begin
      mode_c = 2'd2;
    end else if ((k * ADDRESS_WIDTH) <= NUM_SOURCES) begin
      mode_c = 2'd0;
      n = 0;
      for (i = 0; i < NUM_SOURCES; i = i + 1)
        if (req[i] && n < 4) begin payload_c[n*ADDRESS_WIDTH +: ADDRESS_WIDTH] = i[ADDRESS_WIDTH-1:0]; n = n + 1; end
    end else begin
      mode_c = 2'd2;
      payload_c = req;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      mode <= 2'd2; payload <= {NUM_SOURCES{1'b0}}; valid <= 1'b0; ack_mask <= {NUM_SOURCES{1'b0}};
    end else begin
      mode <= mode_c; payload <= payload_c; valid <= valid_c;
      ack_mask <= valid_c ? req : {NUM_SOURCES{1'b0}};
    end
  end
endmodule
