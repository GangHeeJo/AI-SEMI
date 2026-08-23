// repeat-flag 코덱이 row-trim과 달리 cluster2_steal_buf에도 안전하게 적용되는지 확인.
// repeat-flag는 row 값의 "범위"에 의존하지 않고 그냥 "직전과 완전히 같은가"만 보므로,
// steal이 row 값 범위를 넓히는 것과 무관하게 성립해야 한다는 가설을 실코어로 검증.
`timescale 1ns/1ps
module tb_repeat_encode_steal_buf_check;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0_w; wire [1:0] row0_w; wire [3:0] colmask0_w;
  wire valid1_w; wire [1:0] row1_w; wire [3:0] colmask1_w;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w));

  wire rep0_w, rep1_w;
  wire [31:0] bits_w;
  aer_cluster2_repeat_encode enc(
    .clk(clk), .rst(rst),
    .valid0(valid0_w), .row0(row0_w), .col_mask0(colmask0_w),
    .valid1(valid1_w), .row1(row1_w), .col_mask1(colmask1_w),
    .repeat0(rep0_w), .repeat1(rep1_w), .bits_out(bits_w));

  wire [1:0] link_row0_in = rep0_w ? 2'd0 : row0_w;
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

  integer rng_seed = 5;
  integer cyc, s, draw;
  integer checked, mismatch, repeat_hits, native_bits, repeat_bits;
  reg [3:0] row0_seen, row1_seen;

  initial begin
    rst = 1; arrival = 16'd0;
    checked = 0; mismatch = 0; repeat_hits = 0; native_bits = 0; repeat_bits = 0;
    row0_seen = 4'd0; row1_seen = 4'd0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      arrival = 16'd0;
      // steal을 적극 유발하는 편중 트래픽(§87과 동일 패턴)
      if (cyc % 3 == 0) begin
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if ((s < 4 || s >= 12) && draw < 40) arrival[s] = 1'b1;
        end
      end else if (cyc % 3 == 1) begin
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if ((s >= 4 && s < 12) && draw < 40) arrival[s] = 1'b1;
        end
      end else begin
        for (s = 0; s < 16; s = s + 1) begin
          draw = (($random(rng_seed) % 100 + 100) % 100);
          if (draw < 15) arrival[s] = 1'b1;
        end
      end
      @(posedge clk); #1;

      if (valid0_w) row0_seen[row0_w] = 1'b1;
      if (valid1_w) row1_seen[row1_w] = 1'b1;

      checked = checked + 1;
      if (valid0_w && (drow0 !== row0_w || dcm0 !== colmask0_w)) mismatch = mismatch + 1;
      if (valid1_w && (drow1 !== row1_w || dcm1 !== colmask1_w)) mismatch = mismatch + 1;
      if (rep0_w) repeat_hits = repeat_hits + 1;
      if (rep1_w) repeat_hits = repeat_hits + 1;
      native_bits = native_bits + (valid0_w?7:0) + (valid1_w?7:0);
      repeat_bits = repeat_bits + bits_w;
    end

    $display("row0_seen=%b row1_seen=%b (steal이 3값 전부 도달했는지 확인용)", row0_seen, row1_seen);
    $display("checked=%0d mismatch=%0d repeat_hits=%0d native_bits=%0d repeat_bits=%0d reduction=%0d.%0d%%",
      checked, mismatch, repeat_hits, native_bits, repeat_bits,
      ((native_bits-repeat_bits)*100)/native_bits, (((native_bits-repeat_bits)*1000)/native_bits)%10);
    if (mismatch == 0) $display("REPEAT_ON_STEAL_BUF_PASS");
    else $display("REPEAT_ON_STEAL_BUF_FAIL");
    $finish;
  end
endmodule
