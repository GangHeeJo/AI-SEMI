// repeat-flag 코덱 정확성 검증(실코어+무작위 트래픽). repeat=1인 사이클엔 디코더에
// 들어가는 row/col_mask 입력을 일부러 0으로 지워서(실제 링크에선 전송 안 됨을 흉내)
// 디코더가 진짜로 자기 메모리만으로 복원하는지 확인 -- row/col_mask를 몰래 계속
// 넘겨주면서 "복원됐다"고 착각하는 걸 방지.
`timescale 1ns/1ps
module tb_repeat_encode_correctness;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2 core(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  wire rep0_w, rep1_w;
  wire [31:0] bits_w;
  aer_cluster2_repeat_encode enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .repeat0(rep0_w), .repeat1(rep1_w), .bits_out(bits_w));

  // 인코더 출력(valid0_w 등)은 1사이클 지연된 신호(등록출력)이므로, 디코더에 넣을
  // "이번 사이클 실제 row/col_mask"도 같은 타이밍으로 맞춰야 함 -- valid0_w/row0_w
  // 자체가 이미 그 지연된 신호라 그대로 링크 신호로 재사용(실제로도 이 타이밍에
  // link_valid/link_data가 나감).
  wire [1:0] link_row0_in = rep0_w ? 2'd0 : row0_w;   // repeat면 0으로 지움(전송 안 됨 흉내)
  wire [3:0] link_cm0_in  = rep0_w ? 4'd0 : colmask0_w;
  wire [1:0] link_row1_in = rep1_w ? 2'd0 : row1_w;
  wire [3:0] link_cm1_in  = rep1_w ? 4'd0 : colmask1_w;

  wire [1:0] drow0, drow1; wire [3:0] dcm0, dcm1;
  aer_cluster2_repeat_decode dec(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .repeat0(rep0_w), .row0_in(link_row0_in), .col_mask0_in(link_cm0_in),
    .valid1(valid1_w), .repeat1(rep1_w), .row1_in(link_row1_in), .col_mask1_in(link_cm1_in),
    .row0_out(drow0), .col_mask0_out(dcm0), .row1_out(drow1), .col_mask1_out(dcm1));

  always #5 clk = ~clk;

  integer rng_seed = 13;
  integer cyc, s, draw;
  integer checked, mismatch, repeat_hits, total_bits_native, total_bits_repeat;

  initial begin
    rst = 1; req = 16'd0;
    checked = 0; mismatch = 0; repeat_hits = 0; total_bits_native = 0; total_bits_repeat = 0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      for (s = 0; s < 16; s = s + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 20) req[s] = 1'b1;
      end
      @(posedge clk); #1;
      req = req & ~( (valid0_w ? ({12'b0,colmask0_w} << (row0_w*4)) : 16'd0) |
                      (valid1_w ? ({12'b0,colmask1_w} << (row1_w*4)) : 16'd0) );

      // 디코더가 재구성한 값이 코어의 진짜 값과 일치하는지 확인
      checked = checked + 1;
      if (valid0_w && (drow0 !== row0_w || dcm0 !== colmask0_w)) mismatch = mismatch + 1;
      if (valid1_w && (drow1 !== row1_w || dcm1 !== colmask1_w)) mismatch = mismatch + 1;
      if (rep0_w) repeat_hits = repeat_hits + 1;
      if (rep1_w) repeat_hits = repeat_hits + 1;
      total_bits_native = total_bits_native + (valid0_w?7:0) + (valid1_w?7:0);
      total_bits_repeat = total_bits_repeat + bits_w;
    end

    $display("LIVE_CORE checked=%0d mismatch=%0d repeat_hits=%0d native_bits=%0d repeat_bits=%0d reduction=%0d.%0d%%",
      checked, mismatch, repeat_hits, total_bits_native, total_bits_repeat,
      ((total_bits_native-total_bits_repeat)*100)/total_bits_native,
      (((total_bits_native-total_bits_repeat)*1000)/total_bits_native)%10);
    if (mismatch == 0) $display("REPEAT_CODEC_LIVE_CORE_PASS");
    else $display("REPEAT_CODEC_LIVE_CORE_FAIL");
    $finish;
  end
endmodule
