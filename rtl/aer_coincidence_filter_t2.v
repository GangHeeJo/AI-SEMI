// §50 coincidence filter의 T=1(같은 사이클만) 한계를 넘어선 T=2(2사이클 창) 버전.
// 먼저 온 이벤트를 즉시 버리지 않고 1사이클 붙잡아둠(prev_arrival) -- 그 다음 사이클에
// 같은 블록의 다른 소스가 도착하면(prev든 now든) "확인됨"으로 통과시키고, 아무도 안
// 오면 그때 버림. 출력은 항상 1사이클 지연(원래 도착 사이클 기준 t-1 시점 이벤트를
// t 시점에 최종 판정) -- 모든 소스가 균일하게 1사이클 지연이라 개별 카운터 없이
// "직전+현재 두 사이클의 블록 활동을 OR"만으로 판정 가능(§50처럼 popcount 비교 재사용).
module aer_coincidence_filter_t2 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  output reg [15:0] filtered_arrival, // t-1에 도착한 것 중 확인된 것(t 시점에 출력)
  output reg [15:0] noise_rejected    // t-1에 도착한 것 중 끝내 확인 안 된 것
);
  reg [15:0] prev_arrival;

  wire [15:0] window = prev_arrival | arrival; // [t-1,t] 두 사이클의 블록 활동 합집합

  function [2:0] popcount4;
    input [3:0] v;
    begin
      popcount4 = v[0] + v[1] + v[2] + v[3];
    end
  endfunction

  wire [3:0] tl_bits = {window[5], window[4], window[1], window[0]};
  wire [3:0] tr_bits = {window[7], window[6], window[3], window[2]};
  wire [3:0] bl_bits = {window[13], window[12], window[9], window[8]};
  wire [3:0] br_bits = {window[15], window[14], window[11], window[10]};

  wire pass_tl = (popcount4(tl_bits) >= 3'd2);
  wire pass_tr = (popcount4(tr_bits) >= 3'd2);
  wire pass_bl = (popcount4(bl_bits) >= 3'd2);
  wire pass_br = (popcount4(br_bits) >= 3'd2);

  wire [15:0] blk_tl = 16'b0000000000110011;
  wire [15:0] blk_tr = 16'b0000000011001100;
  wire [15:0] blk_bl = 16'b0011001100000000;
  wire [15:0] blk_br = 16'b1100110000000000;

  wire [15:0] pass_mask = ({16{pass_tl}} & blk_tl) | ({16{pass_tr}} & blk_tr) |
                           ({16{pass_bl}} & blk_bl) | ({16{pass_br}} & blk_br);

  // 판정을 prev_arrival(직전 도착)만 대상으로 하면 비대칭 문제가 생김: prev_arrival이
  // 이번 사이클 새 도착(arrival)에 의해 확인되는 건 잡지만, 그 "새 도착" 쪽 자신은
  // 다음 사이클에 자기 혼자만 놓고(prev_arrival이 이미 넘어가버려서 원래 짝은 잊혀짐)
  // 다시 판정당해 억울하게 반려됨(실측으로 발견 -- cross_cyc 1000/1000으로 절반만 통과).
  // 고침: 이번 사이클에 "직전+지금" 둘 다 훑어서 확인된 건 전부 지금 한꺼번에
  // 통과시키고(filtered_now), 새로 들어온 것 중 아직 확인 안 된 것만 다음 판정으로
  // 넘김(이미 확인된 건 다시 판정 안 되게 제외) -- 이래야 이중판정이 안 생김.
  wire [15:0] filtered_now = (prev_arrival | arrival) & pass_mask;
  wire [15:0] rejected_now = prev_arrival & ~pass_mask;
  wire [15:0] carry_forward = arrival & ~pass_mask;

  always @(posedge clk) begin
    if (rst) begin
      prev_arrival <= 16'd0;
      filtered_arrival <= 16'd0;
      noise_rejected <= 16'd0;
    end else begin
      filtered_arrival <= filtered_now;
      noise_rejected   <= rejected_now;
      prev_arrival <= carry_forward;
    end
  end
endmodule
