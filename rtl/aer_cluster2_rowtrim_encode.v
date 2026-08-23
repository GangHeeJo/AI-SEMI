// cluster2 native 출력(레인당 valid(1)+row(2)+col_mask(4)=7비트, 2레인=14비트)의
// row 필드는 우리 아키텍처(aer_tx16_trad_rowcol_fovea_cluster2.v의 CENTER_MASK=4'b0110/
// PERIPH_MASK=4'b1001) 때문에 실제로는 레인당 2가지 값만 나온다 -- 레인0(중심)은 항상
// row∈{1,2}, 레인1(주변)은 항상 row∈{0,3}(우리가 그 RTL 원본에서 직접 확인함). 2비트로
// 4가지를 표현할 수 있게 잡아놨는데 절반은 원천적으로 안 쓰이므로, 죽은 비트 1개/레인을
// 트림한다. cluster2 RTL은 무수정 -- 이 인코더는 그 뒤에 얹는 순수 조합논리 다운스트림
// 모듈(스위칭/모드선택 없음 -- 오늘(§83~85) 실패한 raw/EF/bitmap 적응형과 원천적으로
// 다른 종류: 그냥 리던던트 비트 제거라 PPA 비용이 사실상 0에 가까울 것으로 기대).
module aer_cluster2_rowtrim_encode (
  input  wire       valid0,
  input  wire [1:0] row0,      // 항상 2'd1 또는 2'd2 (valid0=1일 때)
  input  wire [3:0] col_mask0,
  input  wire       valid1,
  input  wire [1:0] row1,      // 항상 2'd0 또는 2'd3 (valid1=1일 때)
  input  wire [3:0] col_mask1,
  output wire [5:0] lane0_packed, // {valid0, row0_bit, col_mask0}
  output wire [5:0] lane1_packed  // {valid1, row1_bit, col_mask1}
);
  wire row0_bit = (row0 == 2'd2); // 0=row1, 1=row2
  wire row1_bit = (row1 == 2'd3); // 0=row0, 1=row3

  assign lane0_packed = {valid0, row0_bit, col_mask0};
  assign lane1_packed = {valid1, row1_bit, col_mask1};
endmodule
