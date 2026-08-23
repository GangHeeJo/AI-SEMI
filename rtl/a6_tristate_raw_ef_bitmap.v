// 3단 적응형 주소 인코더: raw(저밀도) / Elias-Fano(중밀도) / bitmap(고밀도) 중
// 이번 배치에 실제로 가장 싼 것을 골라 2비트 모드헤더+본문으로 낸다.
// EF 비트계산 로직은 준영 팀 a6_ef_batch_encoder.sv의 검증된 수식을 그대로
// 재사용(§검증 완료: 원본과 K=1,2,4,8,16 전부 동일한 ef_length 나옴 확인됨).
// bitmap 옵션만 새로 추가 -- 이게 이번 3단 적응형의 핵심 기여.
module a6_tristate_raw_ef_bitmap #(
  parameter int NUM_SOURCES = 16,
  parameter int MAX_BATCH = 16,
  parameter int ADDRESS_WIDTH = 4,
  parameter int COUNT_WIDTH = 5
) (
  input  logic [COUNT_WIDTH-1:0]             batch_count,
  input  logic [MAX_BATCH*ADDRESS_WIDTH-1:0] batch_sources, // 오름차순 정렬 가정
  output logic [1:0]                         mode_out,        // 00=raw,01=EF,10=bitmap
  output logic [31:0]                        total_bits_out,
  output logic                               input_error,
  output logic [31:0]                        raw_bits_dbg,
  output logic [31:0]                        ef_bits_dbg
);
  integer raw_length_comb, ef_length_comb, bitmap_length_comb;
  integer low_width_comb;
  integer i, bit_index, zero_index, width_index;
  integer high_value, previous_high, source_value, previous_source;
  integer cursor;

  always_comb begin
    raw_length_comb = batch_count * ADDRESS_WIDTH;
    bitmap_length_comb = NUM_SOURCES; // 위치=주소, 항상 고정
    low_width_comb = 0;
    input_error = (batch_count > MAX_BATCH);
    previous_source = -1;

    // low_width 최적폭 계산 -- 원본 a6_ef_batch_encoder와 동일 수식
    for (width_index = 0; width_index < ADDRESS_WIDTH; width_index = width_index + 1)
      if ((batch_count != 0) &&
          (((1 << (width_index + 1)) * batch_count) <= NUM_SOURCES))
        low_width_comb = width_index + 1;

    // 정렬/범위 검증
    for (i = 0; i < MAX_BATCH; i = i + 1) begin
      source_value = batch_sources[i*ADDRESS_WIDTH +: ADDRESS_WIDTH];
      if (i < batch_count) begin
        if ((source_value >= NUM_SOURCES) ||
            ((previous_source >= 0) && (source_value <= previous_source)))
          input_error = 1'b1;
        previous_source = source_value;
      end
    end

    // EF 본문 길이(count header + unary-high + low bits) -- 원본과 동일 수식
    cursor = COUNT_WIDTH;
    previous_high = 0;
    for (i = 0; i < MAX_BATCH; i = i + 1) begin
      source_value = batch_sources[i*ADDRESS_WIDTH +: ADDRESS_WIDTH];
      if (i < batch_count) begin
        high_value = source_value >> low_width_comb;
        cursor = cursor + (high_value - previous_high) + 1; // gap-zeros + stop-bit
        previous_high = high_value;
      end
    end
    ef_length_comb = cursor + batch_count * low_width_comb;

    raw_bits_dbg = 2 + raw_length_comb;
    ef_bits_dbg = 2 + ef_length_comb;

    // 3단 중 최소 선택, 2비트 모드헤더 고정 포함
    if (input_error) begin
      mode_out = 2'b00;
      total_bits_out = 32'd0;
    end else if ((raw_length_comb <= ef_length_comb) &&
                 (raw_length_comb <= bitmap_length_comb)) begin
      mode_out = 2'b00;
      total_bits_out = 2 + raw_length_comb;
    end else if (ef_length_comb <= bitmap_length_comb) begin
      mode_out = 2'b01;
      total_bits_out = 2 + ef_length_comb;
    end else begin
      mode_out = 2'b10;
      total_bits_out = 2 + bitmap_length_comb;
    end
  end
endmodule
