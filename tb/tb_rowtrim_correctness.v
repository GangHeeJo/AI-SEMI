// aer_cluster2_rowtrim_encode/decode 왕복 정확성 검증. 현수의 3단계 검증(§80/81에서
// 인용)과 같은 방법론을 독립적으로 재현: (1) 도달 가능한 전체 상태(961개, 레인당
// idle 1 + 활성 2행*15열마스크=30 => 31, 31*31=961) 전수 (2) 실제 cluster2 RTL에
// 무작위 트래픽을 흘려서 진짜 출력으로 재확인.
`timescale 1ns/1ps
module tb_rowtrim_correctness;
  // --- (1) 전수(exhaustive) 961개 상태 ---
  reg v0, v1;
  reg [1:0] r0, r1;
  reg [3:0] c0, c1;
  wire [5:0] p0, p1;
  wire dv0, dv1;
  wire [1:0] dr0, dr1;
  wire [3:0] dc0, dc1;

  aer_cluster2_rowtrim_encode enc(
    .valid0(v0), .row0(r0), .col_mask0(c0),
    .valid1(v1), .row1(r1), .col_mask1(c1),
    .lane0_packed(p0), .lane1_packed(p1));
  aer_cluster2_rowtrim_decode dec(
    .lane0_packed(p0), .lane1_packed(p1),
    .valid0(dv0), .row0(dr0), .col_mask0(dc0),
    .valid1(dv1), .row1(dr1), .col_mask1(dc1));

  integer s0, s1, r0i, r1i, c0i, c1i;
  integer total, mismatch;

  task automatic set_lane0;
    input integer sidx; // 0=idle, 1..30 = active(row idx 0/1 * col 1..15)
    begin
      if (sidx == 0) begin v0 = 1'b0; r0 = 2'd1; c0 = 4'd0; end
      else begin
        v0 = 1'b1;
        r0 = ((sidx - 1) / 15) ? 2'd2 : 2'd1;
        c0 = ((sidx - 1) % 15) + 1;
      end
    end
  endtask
  task automatic set_lane1;
    input integer sidx;
    begin
      if (sidx == 0) begin v1 = 1'b0; r1 = 2'd0; c1 = 4'd0; end
      else begin
        v1 = 1'b1;
        r1 = ((sidx - 1) / 15) ? 2'd3 : 2'd0;
        c1 = ((sidx - 1) % 15) + 1;
      end
    end
  endtask

  initial begin
    total = 0; mismatch = 0;
    for (s0 = 0; s0 <= 30; s0 = s0 + 1) begin
      for (s1 = 0; s1 <= 30; s1 = s1 + 1) begin
        set_lane0(s0);
        set_lane1(s1);
        #1;
        total = total + 1;
        if (dv0 !== v0 || dv1 !== v1) mismatch = mismatch + 1;
        else if (v0 && (dr0 !== r0 || dc0 !== c0)) mismatch = mismatch + 1;
        else if (v1 && (dr1 !== r1 || dc1 !== c1)) mismatch = mismatch + 1;
      end
    end
    $display("EXHAUSTIVE total=%0d mismatch=%0d", total, mismatch);
    if (mismatch == 0) $display("ROWTRIM_EXHAUSTIVE_PASS");
    else $display("ROWTRIM_EXHAUSTIVE_FAIL");
  end

  // --- (2) 실제 cluster2 RTL + 무작위 트래픽 ---
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire lv0, lv1;
  wire [1:0] lrow0, lrow1;
  wire [3:0] lcm0, lcm1;
  wire [5:0] lp0, lp1;
  wire ldv0, ldv1;
  wire [1:0] ldr0, ldr1;
  wire [3:0] ldc0, ldc1;

  aer_tx16_trad_rowcol_fovea_cluster2 core(
    .clk(clk), .rst(rst), .req(req),
    .valid0(lv0), .row0(lrow0), .col_mask0(lcm0),
    .valid1(lv1), .row1(lrow1), .col_mask1(lcm1));
  aer_cluster2_rowtrim_encode enc2(
    .valid0(lv0), .row0(lrow0), .col_mask0(lcm0),
    .valid1(lv1), .row1(lrow1), .col_mask1(lcm1),
    .lane0_packed(lp0), .lane1_packed(lp1));
  aer_cluster2_rowtrim_decode dec2(
    .lane0_packed(lp0), .lane1_packed(lp1),
    .valid0(ldv0), .row0(ldr0), .col_mask0(ldc0),
    .valid1(ldv1), .row1(ldr1), .col_mask1(ldc1));

  always #5 clk = ~clk;

  integer rng_seed = 7;
  integer cyc, s, draw;
  integer live_checked, live_mismatch;
  reg [15:0] pending;

  initial begin
    live_checked = 0; live_mismatch = 0;
    pending = 16'd0;
    rst = 1; req = 16'd0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      for (s = 0; s < 16; s = s + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 20 && !pending[s]) pending[s] = 1'b1;
      end
      req = pending;
      @(posedge clk); #1;
      // 이번 사이클 core 출력이 낸 것을 pending에서 제거(다음 재요청 허용)
      if (lv0) for (s = 0; s < 4; s = s + 1) if (lcm0[s]) pending[lrow0*4+s] = 1'b0;
      if (lv1) for (s = 0; s < 4; s = s + 1) if (lcm1[s]) pending[lrow1*4+s] = 1'b0;

      live_checked = live_checked + 1;
      if (ldv0 !== lv0 || ldv1 !== lv1) live_mismatch = live_mismatch + 1;
      else begin
        if (lv0 && (ldr0 !== lrow0 || ldc0 !== lcm0)) live_mismatch = live_mismatch + 1;
        if (lv1 && (ldr1 !== lrow1 || ldc1 !== lcm1)) live_mismatch = live_mismatch + 1;
      end
    end

    $display("LIVE_CORE checked=%0d mismatch=%0d", live_checked, live_mismatch);
    if (live_mismatch == 0) $display("ROWTRIM_LIVE_CORE_PASS");
    else $display("ROWTRIM_LIVE_CORE_FAIL");

    $finish;
  end
endmodule
