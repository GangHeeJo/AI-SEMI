// 1번(주소당 오버헤드) 탐색 -- cluster2(주소기반, row[2b]+col_mask[4b]=6b/grant, 최대
// 2grant/cycle 상한)와 "위치=주소" dense bitmap(매 사이클 16b 통째 전송, 처리용량 무제한
// -- 활성 위치를 전부 동시에 내보낼 수 있음)을 각자의 실제 처리량 모델로 독립적으로
// 돌려서 공정하게 비교한다. 두 스코어보드 모두 "물리적으로 같은 사건 스트림"(공유 RNG
// draw)을 입력받되, 각자의 실제 admission/service 능력에 따라 독립적으로 수락/처리한다.
`timescale 1ns/1ps
module tb_cluster2_bitcost_vs_bitmap;
  parameter N = 16;
  parameter QDEPTH = 4;
  parameter BITMAP_BITS = 16;        // 위치=주소 -- 매 사이클 16b(사건 유무와 무관하게 고정)
  parameter ADDR_BITS_PER_GRANT = 6; // row[1:0](2b) + col_mask[3:0](4b)

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_c2();   // cluster2용
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_bm();   // dense bitmap용(처리용량 무제한)

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, c, idx, lat, s3;
  integer gen_c2, del_c2, overrun_c2, addr_bits_sent;
  integer gen_bm, del_bm, overrun_bm, bitmap_bits_sent;

  task automatic drain_lane_c2;
    input integer valid_in;
    input integer row_in;
    input [3:0] mask_in;
    begin
      if (valid_in) begin
        addr_bits_sent = addr_bits_sent + ADDR_BITS_PER_GRANT;
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            lat = score_c2.record_departure(idx, cyc);
            del_c2 = del_c2 + 1;
          end
        end
      end
    end
  endtask

  // dense bitmap: 처리용량 무제한 -- pending인 소스는 전부 이번 사이클에 즉시 처리(위치
  // 자체가 곧 채널이라 서로 경합하지 않음). 비용은 활성 개수와 무관하게 고정 16b/cycle.
  task automatic drain_bitmap_cycle;
    begin
      bitmap_bits_sent = bitmap_bits_sent + BITMAP_BITS;
      for (s3 = 0; s3 < N; s3 = s3 + 1) begin
        if (score_bm.qcount[s3] > 0) begin
          lat = score_bm.record_departure(s3, cyc);
          del_bm = del_bm + 1;
        end
      end
    end
  endtask

  task automatic run_load_point;
    input integer bg_pct;
    input integer total_cyc;
    integer s, draw;
    begin
      gen_c2=0; del_c2=0; overrun_c2=0; addr_bits_sent=0;
      gen_bm=0; del_bm=0; overrun_bm=0; bitmap_bits_sent=0;
      score_c2.init; score_bm.init;
      for (cyc=0; cyc<total_cyc; cyc=cyc+1) begin
        for (s=0;s<N;s=s+1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw < bg_pct) begin
            if (score_c2.qcount[s] == 0) begin
              gen_c2 = gen_c2 + 1; score_c2.record_arrival(s, cyc);
            end else overrun_c2 = overrun_c2 + 1;
            if (score_bm.qcount[s] == 0) begin
              gen_bm = gen_bm + 1; score_bm.record_arrival(s, cyc);
            end else overrun_bm = overrun_bm + 1;
          end
        end
        for (s=0;s<N;s=s+1) req[s] = (score_c2.qcount[s] > 0);
        @(posedge clk); #1;
        drain_lane_c2(valid0, row0, col_mask0);
        drain_lane_c2(valid1, row1, col_mask1);
        drain_bitmap_cycle;
      end
      req = 16'd0;
      begin : tail
        integer s2, busy, guard;
        busy = 1; guard = 0;
        while (busy && guard < 100000) begin
          for (s2=0;s2<N;s2=s2+1) req[s2] = (score_c2.qcount[s2] > 0);
          @(posedge clk); #1;
          drain_lane_c2(valid0, row0, col_mask0);
          drain_lane_c2(valid1, row1, col_mask1);
          drain_bitmap_cycle;
          cyc = cyc + 1; guard = guard + 1;
          busy = 0;
          if (score_c2.qcount[0]>0) busy=1; // 대표 체크, 아래서 전체 재확인
          busy = 0;
          for (s2=0;s2<N;s2=s2+1)
            if (score_c2.qcount[s2]>0 || score_bm.qcount[s2]>0) busy=1;
        end
      end
      $display("LOAD=%0d%% C2: gen=%0d del=%0d overrun=%0d bits=%0d bits/ev=%0d.%0d | BM: gen=%0d del=%0d overrun=%0d bits=%0d bits/ev=%0d.%0d",
        bg_pct, gen_c2, del_c2, overrun_c2, addr_bits_sent,
        (del_c2>0)?addr_bits_sent/del_c2:0, (del_c2>0)?((addr_bits_sent*10/del_c2)%10):0,
        gen_bm, del_bm, overrun_bm, bitmap_bits_sent,
        (del_bm>0)?bitmap_bits_sent/del_bm:0, (del_bm>0)?((bitmap_bits_sent*10/del_bm)%10):0);
    end
  endtask

  initial begin
    rst = 1; req = 16'd0; cyc = 0;
    score_c2.init; score_bm.init;
    @(posedge clk); #1; rst = 0;

    run_load_point(3, 3000);
    run_load_point(15, 3000);
    run_load_point(30, 3000);
    run_load_point(50, 3000);
    run_load_point(75, 3000);
    run_load_point(100, 3000);
    run_load_point(150, 3000);
    run_load_point(200, 3000);
    run_load_point(400, 3000);

    $display("BITCOST_COMPARISON_DONE");
    $finish;
  end
endmodule
