// 하이브리드(cluster2+dense bitmap 자동전환) 정확성 + 비트비용 실측.
// §69의 cluster2/bitmap 단독 실측치와 같은 부하 스윕으로 비교 가능하게 구성.
`timescale 1ns/1ps
module tb_hybrid_correctness_bitcost;
  parameter N = 16;
  parameter QDEPTH = 4;
  parameter BITMAP_BITS = 16;
  parameter ADDR_BITS_PER_GRANT = 6;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire mode;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;
  wire [15:0] bitmap;

  aer_tx16_hybrid_cluster2_bitmap dut(
    .clk(clk), .rst(rst), .req(req),
    .mode(mode),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1),
    .bitmap(bitmap));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, c, idx, lat;
  integer generated, delivered, overrun, error_count;
  integer bits_sent, addressed_cycles, bitmap_cycles;

  task automatic drain;
    begin
      if (mode) begin
        // dense bitmap: 활성 위치 전부 이번 사이클에 처리
        bits_sent = bits_sent + BITMAP_BITS;
        bitmap_cycles = bitmap_cycles + 1;
        for (c = 0; c < N; c = c + 1) begin
          if (bitmap[c]) begin
            if (score.qcount[c] <= 0) begin
              error_count = error_count + 1;
              $display("PHANTOM(bitmap) cyc=%0d idx=%0d", cyc, c);
            end else begin
              lat = score.record_departure(c, cyc);
              delivered = delivered + 1;
            end
          end
        end
      end else begin
        addressed_cycles = addressed_cycles + 1;
        if (valid0) begin
          bits_sent = bits_sent + ADDR_BITS_PER_GRANT;
          for (c = 0; c < 4; c = c + 1) begin
            if (col_mask0[c]) begin
              idx = row0*4 + c;
              if (score.qcount[idx] <= 0) begin
                error_count = error_count + 1;
                $display("PHANTOM(c2-0) cyc=%0d idx=%0d", cyc, idx);
              end else begin
                lat = score.record_departure(idx, cyc);
                delivered = delivered + 1;
              end
            end
          end
        end
        if (valid1) begin
          bits_sent = bits_sent + ADDR_BITS_PER_GRANT;
          for (c = 0; c < 4; c = c + 1) begin
            if (col_mask1[c]) begin
              idx = row1*4 + c;
              if (score.qcount[idx] <= 0) begin
                error_count = error_count + 1;
                $display("PHANTOM(c2-1) cyc=%0d idx=%0d", cyc, idx);
              end else begin
                lat = score.record_departure(idx, cyc);
                delivered = delivered + 1;
              end
            end
          end
        end
      end
    end
  endtask

  task automatic run_load_point;
    input integer bg_pct;
    input integer total_cyc;
    integer s, draw;
    begin
      generated=0; delivered=0; overrun=0;
      bits_sent=0; addressed_cycles=0; bitmap_cycles=0;
      score.init;
      for (cyc=0; cyc<total_cyc; cyc=cyc+1) begin
        for (s=0;s<N;s=s+1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw < bg_pct) begin
            if (score.qcount[s] == 0) begin
              generated = generated + 1;
              score.record_arrival(s, cyc);
            end else overrun = overrun + 1;
          end
        end
        for (s=0;s<N;s=s+1) req[s] = (score.qcount[s] > 0);
        @(posedge clk); #1;
        drain;
      end
      req = 16'd0;
      begin : tail
        integer s2, busy, guard;
        busy = 1; guard = 0;
        while (busy && guard < 100000) begin
          for (s2=0;s2<N;s2=s2+1) req[s2] = (score.qcount[s2] > 0);
          @(posedge clk); #1;
          drain;
          cyc = cyc + 1; guard = guard + 1;
          busy = 0;
          for (s2=0;s2<N;s2=s2+1) if (score.qcount[s2]>0) busy=1;
        end
      end
      if (generated != delivered) begin
        error_count = error_count + 1;
        $display("COUNT_MISMATCH load=%0d generated=%0d delivered=%0d", bg_pct, generated, delivered);
      end
      $display("LOAD=%0d%% gen=%0d del=%0d overrun=%0d bits=%0d bits/ev=%0d.%0d addr_cyc=%0d bm_cyc=%0d",
        bg_pct, generated, delivered, overrun, bits_sent,
        (delivered>0)?bits_sent/delivered:0, (delivered>0)?((bits_sent*10/delivered)%10):0,
        addressed_cycles, bitmap_cycles);
    end
  endtask

  initial begin
    rst = 1; req = 16'd0; cyc = 0; error_count = 0;
    score.init;
    @(posedge clk); #1; rst = 0;

    run_load_point(3, 3000);
    run_load_point(15, 3000);
    run_load_point(30, 3000);
    run_load_point(50, 3000);
    run_load_point(75, 3000);
    run_load_point(100, 3000);
    run_load_point(150, 3000);
    run_load_point(200, 3000);

    if (error_count == 0)
      $display("HYBRID_CORRECTNESS_BITCOST_PASS");
    else
      $display("HYBRID_CORRECTNESS_BITCOST_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
