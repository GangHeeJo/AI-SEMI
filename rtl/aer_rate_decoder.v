// rate 디코더 -- 생물학적 "누적(leaky integration) 없이 그냥 카운트"의 가장 단순한
// 디지털 버전. 소스마다 "이번 측정 구간(window) 동안 몇 번 grant됐는지"를 세는
// 카운터 16개. 인코딩은 TX(fovea, 무수정) 앞단에서 테스트벤치가 "값 V만큼 여러
// 사이클 req를 켜두는" 방식으로 하고, 이 디코더는 그 grant 횟수를 세서 V를
// 복원하려 시도한다 -- 경합이 없으면 정확히 복원되고, 경합이 있으면 일부 사이클을
// 다른 소스한테 뺏겨서 과소 카운트된다(이게 측정하려는 "값 오차").
module aer_rate_decoder #(
  parameter NUM_SOURCES = 16,
  parameter CNT_WIDTH   = 6   // 0~63까지 카운트(충분히 넉넉하게)
) (
  input                       clk,
  input                       rst,
  input                       valid,       // fovea의 valid
  input  [3:0]                addr,        // fovea의 addr(=grant된 소스 index)
  input                       window_clear, // 이 사이클에 전체 카운터를 0으로 리셋(새 측정 시작)
  output [NUM_SOURCES*CNT_WIDTH-1:0] count_out // 소스별 누적 grant 횟수
);
  reg [CNT_WIDTH-1:0] cnt [0:NUM_SOURCES-1];
  integer k;

  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < NUM_SOURCES; k = k + 1) cnt[k] <= {CNT_WIDTH{1'b0}};
    end else if (window_clear) begin
      for (k = 0; k < NUM_SOURCES; k = k + 1) cnt[k] <= {CNT_WIDTH{1'b0}};
    end else if (valid && (cnt[addr] != {CNT_WIDTH{1'b1}})) begin
      cnt[addr] <= cnt[addr] + 1'b1;
    end
  end

  genvar g;
  generate
    for (g = 0; g < NUM_SOURCES; g = g + 1) begin: pack
      assign count_out[(g+1)*CNT_WIDTH-1 -: CNT_WIDTH] = cnt[g];
    end
  endgenerate
endmodule
