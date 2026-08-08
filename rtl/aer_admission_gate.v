// Homeostatic admission gate -- "손실률을 줄인다"가 아니라(ChatGPT 제안의 이 부분은
// 큐잉이론상 틀림, progress.md 참고: rho>1 지속과부하에서 어디서 버리든 총손실은
// 보존됨) "지연시간을 예측 가능하게 만든다"로 목적을 재정의한 버전.
//
// tx_valid(코어가 이번 사이클에 뭔가를 실제로 내보냈는지)를 leaky bucket으로 누적해서
// 최근 채널 활용률(utilization)을 추정하고, 활용률이 계속 높으면(=지속 과부하 중)
// "새로 들어오려는" 이벤트를 미리 거절한다 -- 이미 밀려있던(pending) 소스의 다음
// 이벤트는 그대로 통과시키고, 완전히 새로 요청하는 소스만 막는다. 그러면 큐가
// 무한정 부풀었다가 늦게 버려지는 대신, 빨리 거절해서 "받아준 것들의" 지연시간을
// 예측 가능한 범위로 묶어둔다.
//
// 하드웨어 비용: 포화 카운터 1개 + 비교기 1개뿐 -- v2/v3(활동량 추적, progress.md
// 5-18에서 면적+688% 확인된 그 계열)와는 전혀 다른 급의 비용.
module aer_admission_gate #(
  parameter UTIL_BITS = 8,
  parameter UTIL_HIGH = 220,  // 255 만점 중 이 이상이면 "과부하" 진입(~86%)
  parameter UTIL_LOW  = 180   // 이 이하로 내려가야 "과부하" 해제(hysteresis로 채터링 방지)
) (
  input         clk,
  input         rst,
  input         tx_valid,     // TX 코어가 이번 사이클에 실제로 뭔가 내보냈는지(피드백)
  input  [15:0] arrival,      // 이번 사이클 "새로 도착한" 이벤트 펄스(소스별, 1사이클)
  input  [15:0] pending,      // 이 소스가 이미 밀려있는 상태인지(테스트벤치/상위 큐 모델 제공)
  output [15:0] admit,        // 실제로 admission을 통과한 이벤트(밀려있던 건 항상 통과)
  output        pressure      // 관측/통계용: 지금 과부하로 판단 중인지
);
  reg [UTIL_BITS-1:0] util_cnt;
  reg pressure_r;
  reg duty_toggle;

  wire [UTIL_BITS-1:0] MAXV = {UTIL_BITS{1'b1}};

  always @(posedge clk) begin
    if (rst) begin
      util_cnt <= {UTIL_BITS{1'b0}};
      pressure_r <= 1'b0;
      duty_toggle <= 1'b0;
    end else begin
      duty_toggle <= ~duty_toggle;
      // leaky bucket: 낼 때마다 1씩 쌓고, 못 낼 때(TX가 쉼)마다 1씩 식힘 -- 최근
      // 활용률의 근사치. 포화(saturate)만 하고 랩어라운드는 절대 안 함.
      if (tx_valid) begin
        if (util_cnt != MAXV) util_cnt <= util_cnt + 1'b1;
      end else begin
        if (util_cnt != {UTIL_BITS{1'b0}}) util_cnt <= util_cnt - 1'b1;
      end

      // 히스테리시스: 높은 문턱을 넘어야 켜지고, 낮은 문턱 밑으로 내려가야 꺼짐 --
      // 문턱 근처에서 매 사이클 켜졌다꺼졌다(채터링) 하는 걸 막는다.
      if (!pressure_r && (util_cnt >= UTIL_HIGH[UTIL_BITS-1:0]))
        pressure_r <= 1'b1;
      else if (pressure_r && (util_cnt <= UTIL_LOW[UTIL_BITS-1:0]))
        pressure_r <= 1'b0;
    end
  end

  assign pressure = pressure_r;
  // v1(폐기): "이미 밀려있던 소스만 통과"는 클러스터링으로 큐가 거의 안 쌓이는
  // 상황에서 "밀려있음" 자체가 드문 상태라 오히려 대부분을 막아버림(실측: 총
  // 거부율 6.9%->57.8%로 폭증, progress.md 참고). 소스 상태와 무관하게 절반만
  // 통과시키는 duty-cycle 방식으로 교체 -- 특정 소스를 차별하지 않고 유입률
  // 자체만 균등하게 줄인다.
  assign admit = pressure_r ? (arrival & {16{duty_toggle}}) : arrival;
endmodule
