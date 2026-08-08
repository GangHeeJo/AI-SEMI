// Dendritic coincidence detection(공간적 상관 필터) -- 통신 압축(cluster류)이 아니라
// "이벤트 자체를 새로 만들지 말지"를 결정하는 계산(computation before communication).
// 4x4를 2x2 블록 4개로 나눠서, 같은 사이클에 한 블록 안에서 2개 이상의 소스가 동시에
// 발화해야만("공간적으로 상관됨" -- 물체 가장자리/움직임처럼) 진짜 이벤트로 통과시키고,
// 블록 안에서 혼자만 발화하면("고립 노이즈") 걸러낸다. lateral inhibition(주변이 발화하면
// 억제)과 정반대 성격 -- 여기선 주변이 같이 발화해야 강화(통과)됨.
//
// 단순화: 이번 구현은 "같은 사이클" 상관만 봄(T=1) -- 실제 생체동역학은 짧은 시간창
// 안의 상관을 보지만, 그러려면 "먼저 온 이벤트를 잠깐 들고 이웃을 기다리는" 상태기계가
// 필요해져서(§44 buffer류와 비슷한 복잡도) 범위를 늘림. 우선 가장 단순한 형태로
// "노이즈 억제가 실제로 되는가"부터 검증.
module aer_coincidence_filter (
  input  [15:0] arrival,          // 원본(필터 전) 도착 펄스
  output [15:0] filtered_arrival, // 블록 내 동시발화 2개 이상 -> 통과
  output [15:0] noise_rejected    // 블록 내 이번 사이클 혼자 -> 억제
);
  // 2x2 블록 매핑: idx=row*4+col. TL={0,1,4,5} TR={2,3,6,7} BL={8,9,12,13} BR={10,11,14,15}
  wire [15:0] blk_tl = 16'b0000000000110011; // bit0,1,4,5
  wire [15:0] blk_tr = 16'b0000000011001100; // bit2,3,6,7
  wire [15:0] blk_bl = 16'b0011001100000000; // bit8,9,12,13
  wire [15:0] blk_br = 16'b1100110000000000; // bit10,11,14,15

  function [2:0] popcount4;
    input [3:0] v;
    begin
      popcount4 = v[0] + v[1] + v[2] + v[3];
    end
  endfunction

  wire [3:0] tl_bits = {arrival[5], arrival[4], arrival[1], arrival[0]};
  wire [3:0] tr_bits = {arrival[7], arrival[6], arrival[3], arrival[2]};
  wire [3:0] bl_bits = {arrival[13], arrival[12], arrival[9], arrival[8]};
  wire [3:0] br_bits = {arrival[15], arrival[14], arrival[11], arrival[10]};

  wire [2:0] cnt_tl = popcount4(tl_bits);
  wire [2:0] cnt_tr = popcount4(tr_bits);
  wire [2:0] cnt_bl = popcount4(bl_bits);
  wire [2:0] cnt_br = popcount4(br_bits);

  wire pass_tl = (cnt_tl >= 3'd2);
  wire pass_tr = (cnt_tr >= 3'd2);
  wire pass_bl = (cnt_bl >= 3'd2);
  wire pass_br = (cnt_br >= 3'd2);

  assign filtered_arrival = arrival &
    ({16{pass_tl}} & blk_tl | {16{pass_tr}} & blk_tr |
     {16{pass_bl}} & blk_bl | {16{pass_br}} & blk_br);
  assign noise_rejected = arrival & ~filtered_arrival;
endmodule
