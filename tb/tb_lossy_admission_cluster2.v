// cluster2(2레인)를 기존 lossy-admission(§29/§36) 조건과 똑같이 재서 cluster(1레인
// 비트맵)와 직접 비교한다.
`timescale 1ns/1ps
module tb_lossy_admission_cluster2;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 16;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req_cluster1, req_cluster2;

  wire valid_c1; wire [1:0] row_c1; wire [3:0] colmask_c1;
  wire valid0_c2; wire [1:0] row0_c2; wire [3:0] colmask0_c2;
  wire valid1_c2; wire [1:0] row1_c2; wire [3:0] colmask1_c2;

  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(5)) tx_cluster1(
    .clk(clk), .rst(rst), .req(req_cluster1), .valid(valid_c1), .row(row_c1), .col_mask(colmask_c1));
  aer_tx16_trad_rowcol_fovea_cluster2 tx_cluster2(
    .clk(clk), .rst(rst), .req(req_cluster2),
    .valid0(valid0_c2), .row0(row0_c2), .col_mask0(colmask0_c2),
    .valid1(valid1_c2), .row1(row1_c2), .col_mask1(colmask1_c2));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_c1();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_c2();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, lat;
  integer gen_center, gen_periph;
  integer drop_center_c1, drop_periph_c1;
  integer drop_center_c2, drop_periph_c2;

  function is_center(input integer idx_);
    is_center = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
  endfunction

  initial begin
    rst = 1; req_cluster1 = 16'd0; req_cluster2 = 16'd0;
    gen_center=0; gen_periph=0;
    drop_center_c1=0; drop_periph_c1=0; drop_center_c2=0; drop_periph_c2=0;
    score_c1.init; score_c2.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          if (is_center(i)) gen_center = gen_center + 1; else gen_periph = gen_periph + 1;
          if (score_c1.qcount[i] >= QDEPTH) begin
            if (is_center(i)) drop_center_c1 = drop_center_c1 + 1; else drop_periph_c1 = drop_periph_c1 + 1;
          end
          if (score_c2.qcount[i] >= QDEPTH) begin
            if (is_center(i)) drop_center_c2 = drop_center_c2 + 1; else drop_periph_c2 = drop_periph_c2 + 1;
          end
          score_c1.record_arrival(i, cyc);
          score_c2.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) begin
        req_cluster1[i] = (score_c1.qcount[i] > 0);
        req_cluster2[i] = (score_c2.qcount[i] > 0);
      end

      @(posedge clk); #1;

      if (valid_c1) begin
        for (c = 0; c < 4; c = c + 1)
          if (colmask_c1[c]) lat = score_c1.record_departure(row_c1*4+c, cyc);
      end
      if (valid0_c2) begin
        for (c = 0; c < 4; c = c + 1)
          if (colmask0_c2[c]) lat = score_c2.record_departure(row0_c2*4+c, cyc);
      end
      if (valid1_c2) begin
        for (c = 0; c < 4; c = c + 1)
          if (colmask1_c2[c]) lat = score_c2.record_departure(row1_c2*4+c, cyc);
      end
    end

    $display("총 생성: center=%0d periph=%0d", gen_center, gen_periph);
    $display("[cluster(1레인)]  center 손실률=%0d.%0d%%  periph 손실률=%0d.%0d%%  전체=%0d.%0d%%",
      (drop_center_c1*100)/gen_center, ((drop_center_c1*1000)/gen_center)%10,
      (drop_periph_c1*100)/gen_periph, ((drop_periph_c1*1000)/gen_periph)%10,
      ((drop_center_c1+drop_periph_c1)*100)/(gen_center+gen_periph), (((drop_center_c1+drop_periph_c1)*1000)/(gen_center+gen_periph))%10);
    $display("[cluster2(2레인)] center 손실률=%0d.%0d%%  periph 손실률=%0d.%0d%%  전체=%0d.%0d%%",
      (drop_center_c2*100)/gen_center, ((drop_center_c2*1000)/gen_center)%10,
      (drop_periph_c2*100)/gen_periph, ((drop_periph_c2*1000)/gen_periph)%10,
      ((drop_center_c2+drop_periph_c2)*100)/(gen_center+gen_periph), (((drop_center_c2+drop_periph_c2)*1000)/(gen_center+gen_periph))%10);
    $finish;
  end
endmodule
