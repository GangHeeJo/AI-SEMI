`timescale 1ns/1ps
// §212: 과부하에서 기존 world_mem_writer(가득 차면 버림)와 world_mem_writer_gain(이득 조절)을 같은 입력으로 비교.
// 프레임마다 640개 이벤트를 열(x) 순서로 8개/사이클 속도로 쏘고, 프레임 주기 T사이클(쓰기 포트는 1건/사이클)로 쓰기 용량 비율 f = T/640을 만든다.
// 장면: x=y 대각선 띠(열마다 8개 띠 이벤트 + 2개 무작위). 지표: 정답(들어온 전부)과 쓰인 이벤트의 칸별 개수 지도의 NCC, x 사분위별 남은 비율, 손실/솎아냄 개수.
// 실행: vvp ... +T=160  (T 기본 160 -> f=0.25)
module tb_gain_overload;
  localparam NL = 8, AB = 6, E = 640, NFR = 300, WARM = 20;
  reg clk = 0, rst = 1; always #2.5 clk = ~clk;
  reg [NL-1:0] valid = 0; reg [NL*AB-1:0] wx = 0, wy = 0; reg [NL-1:0] wp = 0;
  wire [NL-1:0] ov_a, ov_b, shed_b; wire stall_a, stall_b, we_a, we_b, pol_a, pol_b; wire [2*AB-1:0] ad_a, ad_b;
  world_mem_writer      #(.N_LANES(NL), .ADDR_BITS(AB), .FIFO_DEPTH(32)) A (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .wr_overrun(ov_a), .stall(stall_a), .world_we(we_a), .world_addr(ad_a), .world_pol(pol_a));
  world_mem_writer_gain #(.N_LANES(NL), .ADDR_BITS(AB), .FIFO_DEPTH(32)) B (.clk(clk), .rst(rst), .wr_valid(valid), .wr_x(wx), .wr_y(wy), .wr_pol(wp), .wr_overrun(ov_b), .wr_shed(shed_b), .stall(stall_b), .world_we(we_b), .world_addr(ad_b), .world_pol(pol_b));

  integer full_m [0:4095]; integer ma [0:4095]; integer mb [0:4095];
  integer qa [0:3]; integer qb [0:3]; integer qf [0:3];
  integer ex [0:E-1]; integer ey [0:E-1]; integer seed, T, fr, c, i, j, k, n_over_a, n_over_b, n_shed_b, n_all, n_wa, n_wb;
  initial begin
    seed = 99; T = 160; if (!$value$plusargs("T=%d", T)) T = 160;
    for (i = 0; i < 4096; i = i + 1) begin full_m[i] = 0; ma[i] = 0; mb[i] = 0; end
    for (i = 0; i < 4; i = i + 1) begin qa[i] = 0; qb[i] = 0; qf[i] = 0; end
    n_over_a = 0; n_over_b = 0; n_shed_b = 0; n_all = 0; n_wa = 0; n_wb = 0;
    repeat (4) @(posedge clk); #1 rst = 0;
    for (fr = 0; fr < NFR; fr = fr + 1) begin
      if (fr == WARM) begin
        for (i = 0; i < 4096; i = i + 1) begin full_m[i] = 0; ma[i] = 0; mb[i] = 0; end
        for (i = 0; i < 4; i = i + 1) begin qa[i] = 0; qb[i] = 0; qf[i] = 0; end
        n_over_a = 0; n_over_b = 0; n_shed_b = 0; n_all = 0; n_wa = 0; n_wb = 0;
      end
      k = 0;
      for (c = 0; c < 64; c = c + 1) for (j = 0; j < 10; j = j + 1) begin
        ex[k] = c;
        if (j < 8) begin ey[k] = c + (($random(seed) & 32'h7fffffff) % 7) - 3; if (ey[k] < 0) ey[k] = 0; if (ey[k] > 63) ey[k] = 63; end
        else ey[k] = ($random(seed) & 32'h7fffffff) % 64;
        full_m[ey[k]*64 + ex[k]] = full_m[ey[k]*64 + ex[k]] + 1; qf[ex[k] / 16] = qf[ex[k] / 16] + 1; n_all = n_all + 1; k = k + 1;
      end
      for (c = 0; c < T; c = c + 1) begin
        @(negedge clk); valid = 0;
        if (c < E / NL) for (j = 0; j < NL; j = j + 1) begin
          valid[j] = 1; wx[j*AB +: AB] = ex[c*NL + j]; wy[j*AB +: AB] = ey[c*NL + j]; wp[j] = $random(seed);
        end
      end
    end
    @(negedge clk); valid = 0; repeat (400) @(posedge clk);
    $display("T=%0d  f=%0.3f  frames=%0d (after %0d warm-up)  events=%0d", T, T * 1.0 / E, NFR - WARM, WARM, n_all);
    $display("A tail-drop: written=%0d (%0.1f%%) overrun=%0d  | kept by x-quartile: %0.1f %0.1f %0.1f %0.1f %%", n_wa, n_wa * 100.0 / n_all, n_over_a, qa[0]*100.0/qf[0], qa[1]*100.0/qf[1], qa[2]*100.0/qf[2], qa[3]*100.0/qf[3]);
    $display("B gain     : written=%0d (%0.1f%%) overrun=%0d shed=%0d | kept by x-quartile: %0.1f %0.1f %0.1f %0.1f %%", n_wb, n_wb * 100.0 / n_all, n_over_b, n_shed_b, qb[0]*100.0/qf[0], qb[1]*100.0/qf[1], qb[2]*100.0/qf[2], qb[3]*100.0/qf[3]);
    $display("NCC vs all-events map: A=%0.3f  B=%0.3f", ncc_a(0), ncc_a(1));
    $finish;
  end
  always @(posedge clk) if (!rst) begin
    if (we_a) begin ma[ad_a[11:6]*64 + ad_a[5:0]] = ma[ad_a[11:6]*64 + ad_a[5:0]] + 1; qa[ad_a[5:0] / 16] = qa[ad_a[5:0] / 16] + 1; n_wa = n_wa + 1; end
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
