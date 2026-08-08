// addr_encode16/addr_decode16 검증: (1) 16개 주소 전부 왕복 무결성(encode->decode==원본),
// (2) 평균 코드 길이를 실제 트래픽 분포(핫스팟식 편중 vs 균일)에서 재서 고정 4비트
// 대비 절감폭을 확인 — 가정(중심이 더 잦음)이 틀리면 절감이 안 된다는 것도 정직하게 봄.
`timescale 1ns/1ps
module tb_addr_codec;
  reg  [3:0] addr_in;
  wire [4:0] code;
  wire [2:0] len;
  wire [3:0] addr_out;
  wire [2:0] dec_len;

  addr_encode16 enc(.addr(addr_in), .code(code), .len(len));
  addr_decode16 dec(.buf5(code), .addr(addr_out), .len(dec_len));

  integer i, errors;
  integer rng_seed;
  integer draw, cyc, addr_sel;
  integer sum_len_skew, sum_len_uniform, n_skew, n_uniform;

  initial begin
    errors = 0;
    // (1) 왕복 무결성 전수 검사
    for (i = 0; i < 16; i = i + 1) begin
      addr_in = i[3:0];
      #1;
      if (addr_out !== addr_in[3:0]) begin
        $display("FAIL: addr=%0d encode/decode 왕복 실패(복원=%0d)", addr_in, addr_out);
        errors = errors + 1;
      end
      if (dec_len !== len) begin
        $display("FAIL: addr=%0d 인코더/디코더 길이 불일치(enc=%0d dec=%0d)", addr_in, len, dec_len);
        errors = errors + 1;
      end
    end
    if (errors == 0) $display("[1] 16개 주소 전부 왕복 무결성 통과");

    // (2) 평균 코드 길이 실측 — 핫스팟식 편중(중심 15%, 주변 2%) vs 완전 균일
    rng_seed = 1;
    sum_len_skew = 0; n_skew = 0;
    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      for (addr_sel = 0; addr_sel < 16; addr_sel = addr_sel + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ((addr_sel==5||addr_sel==6||addr_sel==9||addr_sel==10) ? 15 : 2)) begin
          addr_in = addr_sel[3:0]; #1;
          sum_len_skew = sum_len_skew + len; n_skew = n_skew + 1;
        end
      end
    end
    $display("[2] 편중 트래픽(중심15%%/주변2%%): 평균 코드길이=%0d.%0d bit (표본 %0d개), 고정4bit 대비 %0d%% 절감",
      sum_len_skew/n_skew, ((sum_len_skew*10)/n_skew)%10, n_skew,
      100 - (sum_len_skew*100)/(n_skew*4));

    rng_seed = 1;
    sum_len_uniform = 0; n_uniform = 0;
    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      for (addr_sel = 0; addr_sel < 16; addr_sel = addr_sel + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 5) begin // 완전 균일(전부 5%)
          addr_in = addr_sel[3:0]; #1;
          sum_len_uniform = sum_len_uniform + len; n_uniform = n_uniform + 1;
        end
      end
    end
    $display("[3] 균일 트래픽(전부5%%):        평균 코드길이=%0d.%0d bit (표본 %0d개), 고정4bit 대비 %0d%% 절감(가정이 틀리면?)",
      sum_len_uniform/n_uniform, ((sum_len_uniform*10)/n_uniform)%10, n_uniform,
      100 - (sum_len_uniform*100)/(n_uniform*4));

    $finish;
  end
endmodule
