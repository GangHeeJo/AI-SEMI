// cluster2_dynamic(top-2 동적 레인배정)을 §29/§36/§43과 동일한 lossy-admission
// 조건(QDEPTH=16)으로 cluster2(팀 고정 레인)와 나란히 비교.
`timescale 1ns/1ps
module tb_lossy_admission_cluster2_dynamic;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 16;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] req_fixed, req_dyn;

  wire valid0_f; wire [1:0] row0_f; wire [3:0] colmask0_f;
  wire valid1_f; wire [1:0] row1_f; wire [3:0] colmask1_f;
  wire valid0_d; wire [1:0] row0_d; wire [3:0] colmask0_d;
  wire valid1_d; wire [1:0] row1_d; wire [3:0] colmask1_d;

  aer_tx16_trad_rowcol_fovea_cluster2 tx_fixed(
    .clk(clk), .rst(rst), .req(req_fixed),
    .valid0(valid0_f), .row0(row0_f), .col_mask0(colmask0_f),
    .valid1(valid1_f), .row1(row1_f), .col_mask1(colmask1_f));
  aer_tx16_trad_rowcol_fovea_cluster2_dynamic tx_dyn(
    .clk(clk), .rst(rst), .req(req_dyn),
    .valid0(valid0_d), .row0(row0_d), .col_mask0(colmask0_d),
    .valid1(valid1_d), .row1(row1_d), .col_mask1(colmask1_d));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_f();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_d();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, lat;
  integer generated, drop_f, drop_d;

  initial begin
    rst = 1; req_fixed = 16'd0; req_dyn = 16'd0;
    generated = 0; drop_f = 0; drop_d = 0;
    score_f.init; score_d.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          if (score_f.qcount[i] >= QDEPTH) drop_f = drop_f + 1;
          if (score_d.qcount[i] >= QDEPTH) drop_d = drop_d + 1;
          score_f.record_arrival(i, cyc);
          score_d.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) begin
        req_fixed[i] = (score_f.qcount[i] > 0);
        req_dyn[i]   = (score_d.qcount[i] > 0);
      end

      @(posedge clk); #1;

      if (valid0_f) for (c = 0; c < 4; c = c + 1) if (colmask0_f[c]) lat = score_f.record_departure(row0_f*4+c, cyc);
      if (valid1_f) for (c = 0; c < 4; c = c + 1) if (colmask1_f[c]) lat = score_f.record_departure(row1_f*4+c, cyc);
      if (valid0_d) for (c = 0; c < 4; c = c + 1) if (colmask0_d[c]) lat = score_d.record_departure(row0_d*4+c, cyc);
      if (valid1_d) for (c = 0; c < 4; c = c + 1) if (colmask1_d[c]) lat = score_d.record_departure(row1_d*4+c, cyc);
    end

    $display("generated=%0d", generated);
    $display("[cluster2 고정레인]  drop=%0d  손실률=%0d.%0d%%",
      drop_f, (drop_f*100)/generated, ((drop_f*1000)/generated)%10);
    $display("[cluster2_dynamic]   drop=%0d  손실률=%0d.%0d%%",
      drop_d, (drop_d*100)/generated, ((drop_d*1000)/generated)%10);
    $finish;
  end
endmodule
