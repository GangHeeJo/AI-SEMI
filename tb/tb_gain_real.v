`timescale 1ns/1ps
`ifndef FDA
 `define FDA 32
`endif
`ifndef FDB
 `define FDB 32
`endif
`ifndef CN
 `define CN 64
`endif
// §215(실제 DELTA 이벤트 입력판): tb/delta_events_64.txt(export_delta_cells.py)를 640개씩 프레임으로 쏜다. 나머지는 tb_gain_overload.v와 같음.
// §212: 과부하에서 기존 world_mem_writer(가득 차면 버림)와 world_mem_writer_gain(이득 조절)을 같은 입력으로 비교.
// 프레임마다 640개 이벤트를 열(x) 순서로 8개/사이클 속도로 쏘고, 프레임 주기 T사이클(쓰기 포트는 1건/사이클)로 쓰기 용량 비율 f = T/640을 만든다.
// 장면: x=y 대각선 띠(열마다 8개 띠 이벤트 + 2개 무작위). 지표: 정답(들어온 전부)과 쓰인 이벤트의 칸별 개수 지도의 NCC, x 사분위별 남은 비율, 손실/솎아냄 개수.
// 실행: vvp ... +T=160  (T 기본 160 -> f=0.25)
module tb_gain_overload;
  localparam NL = 8, AB = 6, E = 32000, NFR = 8, WARM = 2;   // 프레임 = 실제 이벤트 32000개(센서 프레임 하나가 약 36000개)
  reg clk = 0, rst = 1; always #2.5 clk = ~clk;
  reg [NL-1:0] valid = 0; reg [NL*AB-1:0] wx = 0, wy = 0; reg [NL-1:0] wp = 0;
  wire [NL-1:0] ov_a, ov_b, shed_b, ov_c, shed_c; wire dedup_b, dedup_c, stall_c, we_c, pol_c; wire [2*AB-1:0] ad_c; wire stall_a, stall_b, we_a, we_b, pol_a, pol_b; wire [2*AB-1:0] ad_a, ad_b;
  world_mem_writer      #(.N_LANES(NL), .ADDR_BITS(AB), .FIFO_DEPTH(`FDA)) A (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .wr_overrun(ov_a), .stall(stall_a), .world_we(we_a), .world_addr(ad_a), .world_pol(pol_a));
  world_mem_writer_gain #(.N_LANES(NL), .ADDR_BITS(AB), .FIFO_DEPTH(`FDB)) B (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .wr_overrun(ov_b), .wr_shed(shed_b), .wr_dedup(dedup_b), .stall(stall_b), .world_we(we_b), .world_addr(ad_b), .world_pol(pol_b));

  world_mem_writer_gain #(.N_LANES(NL), .ADDR_BITS(AB), .FIFO_DEPTH(`FDB), .CACHE_N(`CN)) Cc (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .wr_overrun(ov_c), .wr_shed(shed_c), .wr_dedup(dedup_c), .stall(stall_c), .world_we(we_c), .world_addr(ad_c), .world_pol(pol_c));

  integer full_m [0:4095]; integer ma [0:4095]; integer mb [0:4095]; integer mc [0:4095];
  reg vb [0:4095]; reg pb [0:4095]; reg vc [0:4095]; reg pc [0:4095]; integer epol [0:E-1]; integer n_wc, n_dedup_c, n_we_c, n_mism;
  integer qa [0:3]; integer qb [0:3]; integer qf [0:3];
  integer rx [0:NFR*E-1]; integer ry [0:NFR*E-1]; integer rp [0:NFR*E-1]; integer fd;
  integer ex [0:E-1]; integer ey [0:E-1]; integer seed, T, fr, c, i, j, k, n_over_a, n_over_b, n_shed_b, n_all, n_wa, n_wb;
  initial begin
    seed = 99; T = 160; if (!$value$plusargs("T=%d", T)) T = 160;
    for (i = 0; i < 4096; i = i + 1) begin full_m[i] = 0; ma[i] = 0; mb[i] = 0; mc[i] = 0; vb[i] = 0; pb[i] = 0; vc[i] = 0; pc[i] = 0; end
    for (i = 0; i < 4; i = i + 1) begin qa[i] = 0; qb[i] = 0; qf[i] = 0; end
    n_wc = 0; n_dedup_c = 0; n_we_c = 0; n_mism = 0; n_over_a = 0; n_over_b = 0; n_shed_b = 0; n_all = 0; n_wa = 0; n_wb = 0;
    fd = $fopen("tb/delta_events_64.txt", "r");
    for (i = 0; i < NFR*E; i = i + 1) begin if ($fscanf(fd, "%d %d %d", rx[i], ry[i], rp[i]) != 3) begin $display("READ_FAIL %0d", i); $finish; end end
    $fclose(fd);
    repeat (4) @(posedge clk); #1 rst = 0;
    for (fr = 0; fr < NFR; fr = fr + 1) begin
      if (fr == WARM) begin
        for (i = 0; i < 4096; i = i + 1) begin full_m[i] = 0; ma[i] = 0; mb[i] = 0; end
        for (i = 0; i < 4; i = i + 1) begin qa[i] = 0; qb[i] = 0; qf[i] = 0; end
        n_over_a = 0; n_over_b = 0; n_shed_b = 0; n_all = 0; n_wa = 0; n_wb = 0; n_we_c = 0; n_dedup_c = 0;
      end
      for (k = 0; k < E; k = k + 1) begin
        ex[k] = rx[fr*E + k]; ey[k] = ry[fr*E + k]; epol[k] = rp[fr*E + k];
        full_m[ey[k]*64 + ex[k]] = full_m[ey[k]*64 + ex[k]] + 1; qf[ex[k] / 16] = qf[ex[k] / 16] + 1; n_all = n_all + 1;
      end
      for (c = 0; c < T; c = c + 1) begin
        @(negedge clk); valid = 0;
        if (c < E / NL) for (j = 0; j < NL; j = j + 1) begin
          valid[j] = 1; wx[j*AB +: AB] = ex[c*NL + j]; wy[j*AB +: AB] = ey[c*NL + j]; wp[j] = epol[c*NL + j];
        end
      end
    end
    @(negedge clk); valid = 0; repeat (400) @(posedge clk);
    $display("T=%0d  f=%0.3f  frames=%0d (after %0d warm-up)  events=%0d", T, T * 1.0 / E, NFR - WARM, WARM, n_all);
    $display("A tail-drop: written=%0d (%0.1f%%) overrun=%0d  | kept by x-quartile: %0.1f %0.1f %0.1f %0.1f %%", n_wa, n_wa * 100.0 / n_all, n_over_a, qa[0]*100.0/qf[0], qa[1]*100.0/qf[1], qa[2]*100.0/qf[2], qa[3]*100.0/qf[3]);
    $display("B gain     : written=%0d (%0.1f%%) overrun=%0d shed=%0d | kept by x-quartile: %0.1f %0.1f %0.1f %0.1f %%", n_wb, n_wb * 100.0 / n_all, n_over_b, n_shed_b, qb[0]*100.0/qf[0], qb[1]*100.0/qf[1], qb[2]*100.0/qf[2], qb[3]*100.0/qf[3]);
    $display("NCC vs all-events map: A=%0.3f  B=%0.3f", ncc_a(0), ncc_a(1));
    for (i = 0; i < 4096; i = i + 1) if (vb[i] !== vc[i] || (vb[i] && pb[i] !== pc[i])) n_mism = n_mism + 1;
    $display("C gain+cache(%0d): memory writes issued=%0d  dedup(skipped)=%0d (%0.1f%% of grants)  | final memory image vs B(gain only): mismatching cells=%0d", `CN, n_we_c, n_dedup_c, n_dedup_c * 100.0 / (n_we_c + n_dedup_c + 1e-9), n_mism);
    $finish;
  end
  always @(posedge clk) if (!rst) begin
    if (we_a) begin ma[ad_a[11:6]*64 + ad_a[5:0]] = ma[ad_a[11:6]*64 + ad_a[5:0]] + 1; qa[ad_a[5:0] / 16] = qa[ad_a[5:0] / 16] + 1; n_wa = n_wa + 1; end
    if (we_c) begin vc[ad_c[11:6]*64 + ad_c[5:0]] = 1; pc[ad_c[11:6]*64 + ad_c[5:0]] = pol_c; n_we_c = n_we_c + 1; end
    if (dedup_c) n_dedup_c = n_dedup_c + 1;
    if (we_b) begin vb[ad_b[11:6]*64 + ad_b[5:0]] = 1; pb[ad_b[11:6]*64 + ad_b[5:0]] = pol_b; end
    if (we_b) begin mb[ad_b[11:6]*64 + ad_b[5:0]] = mb[ad_b[11:6]*64 + ad_b[5:0]] + 1; qb[ad_b[5:0] / 16] = qb[ad_b[5:0] / 16] + 1; n_wb = n_wb + 1; end
    n_over_a = n_over_a + ov_a[0] + ov_a[1] + ov_a[2] + ov_a[3] + ov_a[4] + ov_a[5] + ov_a[6] + ov_a[7];
    n_over_b = n_over_b + ov_b[0] + ov_b[1] + ov_b[2] + ov_b[3] + ov_b[4] + ov_b[5] + ov_b[6] + ov_b[7];
    n_shed_b = n_shed_b + shed_b[0] + shed_b[1] + shed_b[2] + shed_b[3] + shed_b[4] + shed_b[5] + shed_b[6] + shed_b[7];
  end
  function real ncc_a(input integer which);
    real mu, mv, su, sv, suv, u, v; integer q;
    begin
      mu = 0; mv = 0; for (q = 0; q < 4096; q = q + 1) begin mu = mu + full_m[q]; mv = mv + (which ? mb[q] : ma[q]); end
      mu = mu / 4096.0; mv = mv / 4096.0; su = 0; sv = 0; suv = 0;
      for (q = 0; q < 4096; q = q + 1) begin u = full_m[q] - mu; v = (which ? mb[q] : ma[q]) - mv; su = su + u * u; sv = sv + v * v; suv = suv + u * v; end
      ncc_a = suv / ($sqrt(su) * $sqrt(sv) + 1e-12);
    end
  endfunction
endmodule
