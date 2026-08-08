// [틀깨기 실험 B] 가변길이 주소 부호화(Entropy Coding) — 핀 수 문제를 burst(시간을
// 더 써서 핀을 아낌)가 아니라 정보이론(통계적으로 흔한 주소는 짧게)으로 공격.
// fovea가 만든 "중심이 통계적으로 더 자주 쓰인다"는 사실을 재활용: 2단 프리픽스
// 코드 — 태그 1비트(0=중심그룹/1=주변그룹) + 중심이면 2비트(4개 구분), 주변이면
// 4비트(12개 구분, 일부 코드는 안 씀). 중심 3비트/주변 5비트, 고정 4비트 대비
// 평균 비트수가 준다(실제 절감폭은 실측 트래픽 분포에 좌우됨 — tb_addr_codec_gain.v).
// 직렬(serial) 전송(burst/inter-chip 시나리오처럼 핀이 적은 상황)에 결합하면 평균
// 사이클수를 줄이는 용도 — 병렬 버스(지금 우리 메인 설계)에서는 핀 절감 효과 없음,
// "핀이 진짜 부족한 상황"의 추가 개선 레버로 검토.
module addr_encode16(
  input      [3:0] addr,       // {row[1:0],col[1:0]}
  output reg [4:0] code,       // 좌측정렬(MSB부터), len 만큼만 유효
  output reg [2:0] len         // 실제 코드 길이(3 또는 5)
);
  wire is_center = (addr==4'd5) || (addr==4'd6) || (addr==4'd9) || (addr==4'd10);
  reg [1:0] center_idx;
  reg [3:0] periph_idx;

  always @(*) begin
    case (addr)
      4'd5:  center_idx = 2'd0;
      4'd6:  center_idx = 2'd1;
      4'd9:  center_idx = 2'd2;
      default: center_idx = 2'd3; // 4'd10
    endcase
    // 주변 12개(0,1,2,3,4,7,8,11,12,13,14,15) -> 0..11
    case (addr)
      4'd0: periph_idx=4'd0;   4'd1: periph_idx=4'd1;   4'd2: periph_idx=4'd2;   4'd3: periph_idx=4'd3;
      4'd4: periph_idx=4'd4;   4'd7: periph_idx=4'd5;   4'd8: periph_idx=4'd6;   4'd11: periph_idx=4'd7;
      4'd12: periph_idx=4'd8;  4'd13: periph_idx=4'd9;  4'd14: periph_idx=4'd10; default: periph_idx=4'd11; // 4'd15
    endcase

    if (is_center) begin
      code = {1'b0, center_idx, 2'b00}; // 상위 3비트만 유효(좌측정렬)
      len  = 3'd3;
    end else begin
      code = {1'b1, periph_idx};        // 5비트 전부 유효
      len  = 3'd5;
    end
  end
endmodule

// 디코더: 좌측정렬된 최대 5비트 버퍼(shift-in, MSB부터)를 받아 태그로 실제 길이를
// 알아내고 addr을 복원. combinational(조합논리) — 상위 호출부가 몇 비트 shift-in
// 됐는지 추적해서 충분히 모이면 decode_valid로 알려주는 구조.
module addr_decode16(
  input      [4:0] buf5,        // 좌측정렬 누적 버퍼(최소 3비트 이상 채워졌다고 가정)
  output reg [3:0] addr,
  output reg [2:0] len          // 실제 소비한 비트 수(3 또는 5) — 상위에서 버퍼 shift에 사용
);
  wire tag = buf5[4];
  reg [1:0] center_idx;
  reg [3:0] periph_idx;
  always @(*) begin
    center_idx = buf5[3:2];
    periph_idx = buf5[3:0];
    if (tag == 1'b0) begin
      len = 3'd3;
      case (center_idx)
        2'd0: addr = 4'd5;
        2'd1: addr = 4'd6;
        2'd2: addr = 4'd9;
        default: addr = 4'd10;
      endcase
    end else begin
      len = 3'd5;
      case (periph_idx)
        4'd0: addr=4'd0;   4'd1: addr=4'd1;   4'd2: addr=4'd2;   4'd3: addr=4'd3;
        4'd4: addr=4'd4;   4'd5: addr=4'd7;   4'd6: addr=4'd8;   4'd7: addr=4'd11;
        4'd8: addr=4'd12;  4'd9: addr=4'd13;  4'd10: addr=4'd14; default: addr=4'd15;
      endcase
    end
  end
endmodule

// 인코더+디코더 합산 PPA 확인용 래퍼(왕복 경로 하나로 묶어서 합성).
module addr_codec16_pair(
  input      [3:0] addr,
  output     [3:0] addr_roundtrip,
  output     [2:0] enc_len
);
  wire [4:0] code;
  wire [2:0] dec_len;
  addr_encode16 enc(.addr(addr), .code(code), .len(enc_len));
  addr_decode16 dec(.buf5(code), .addr(addr_roundtrip), .len(dec_len));
endmodule
