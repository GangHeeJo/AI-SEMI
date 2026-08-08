// 최소 수신부(RX) -- TX(cluster2_steal_buf)가 내보내는 row+col_mask 2레인을 소스별
// valid 16개로 복원한다. "주소=이벤트" 철학 그대로: payload가 없으니 복원할 값도
// 없고, 그냥 "이 소스가 지금 발화했다"만 재구성하면 됨 -- 순수 조합논리(레지스터 없음).
// 의미 해석(좌표변환/월드메모리 매핑)은 2차 과제 범위라 여기선 안 함.
module aer_rx16_steal_buf (
  input         valid0,
  input  [1:0]  row0,
  input  [3:0]  col_mask0,
  input         valid1,
  input  [1:0]  row1,
  input  [3:0]  col_mask1,
  output [15:0] source_valid // 소스별 "이번 사이클 이벤트 도착"
);
  wire [15:0] lane0_bits = valid0 ? (col_mask0 << (row0*4)) : 16'd0;
  wire [15:0] lane1_bits = valid1 ? (col_mask1 << (row1*4)) : 16'd0;
  // lane0/lane1은 항상 서로 다른 행을 가리키므로(TX 쪽 주석 참고) 단순 OR로 충분.
  assign source_valid = lane0_bits | lane1_bits;
endmodule
