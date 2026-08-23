// cluster2(round-robin) vs cluster2_globalhold(진짜 Gen3식 스냅샷)를 완전히 동일한
// 물리적 이벤트 스트림으로 나란히 돌려서, ground-truth 기준 jitter(§67/§68과 동일
// 정의: 같은 소스 연속 이벤트의 latency 변동폭)가 Global Hold로 실제 줄어드는지 검증.
// tb_cluster2_tdm_vs_baseline.v와 완전히 동일한 구조(TDM 대신 globalhold만 교체).
`timescale 1ns/1ps
module tb_cluster2_globalhold_vs_baseline;
  parameter N = 16;
  parameter QDEPTH = 4;
  parameter HOLD_PERIOD = 4;

  reg clk = 0;
  reg rst;
  reg [15:0] req_base, req_gh;

  wire valid0_b; wire [1:0] row0_b; wire [3:0] col_mask0_b;
  wire valid1_b; wire [1:0] row1_b; wire [3:0] col_mask1_b;
  aer_tx16_trad_rowcol_fovea_cluster2 dut_base(
    .clk(clk), .rst(rst), .req(req_base),
    .valid0(valid0_b), .row0(row0_b), .col_mask0(col_mask0_b),
    .valid1(valid1_b), .row1(row1_b), .col_mask1(col_mask1_b));

  wire valid0_g; wire [1:0] row0_g; wire [3:0] col_mask0_g;
  wire valid1_g; wire [1:0] row1_g; wire [3:0] col_mask1_g;
  aer_tx16_trad_rowcol_fovea_cluster2_globalhold #(.HOLD_PERIOD(HOLD_PERIOD)) dut_gh(
    .clk(clk), .rst(rst), .req(req_gh),
    .valid0(valid0_g), .row0(row0_g), .col_mask0(col_mask0_g),
    .valid1(valid1_g), .row1(row1_g), .col_mask1(col_mask1_g));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_b();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_g();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, c, idx, lat;
  integer gen_b, del_b, overrun_b, err_b;
  integer gen_g, del_g, overrun_g, err_g;
  integer total_err;

  integer last_lat_b [0:N-1]; integer have_last_b [0:N-1];
  integer last_lat_g [0:N-1]; integer have_last_g [0:N-1];
  integer jit_sum_b, jit_cnt_b, jit_sum_g, jit_cnt_g;
  integer max_lat_b, max_lat_g;

  function integer abs_i;
    input integer x;
    begin
      abs_i = (x < 0) ? -x : x;
    end
  endfunction

  task automatic drain_dut;
    input integer valid_in;
    input integer row_in;
    input [3:0] mask_in;
    input integer is_gh;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (is_gh) begin
              if (score_g.qcount[idx] <= 0) begin
                err_g = err_g + 1;
              end else begin
                lat = score_g.record_departure(idx, cyc);
                del_g = del_g + 1;
                if (lat > max_lat_g) max_lat_g = lat;
                if (have_last_g[idx]) begin
                  jit_sum_g = jit_sum_g + abs_i(lat - last_lat_g[idx]);
                  jit_cnt_g = jit_cnt_g + 1;
                end
                last_lat_g[idx] = lat; have_last_g[idx] = 1;
              end
            end else begin
              if (score_b.qcount[idx] <= 0) begin
                err_b = err_b + 1;
              end else begin
                lat = score_b.record_departure(idx, cyc);
                del_b = del_b + 1;
                if (lat > max_lat_b) max_lat_b = lat;
                if (have_last_b[idx]) begin
                  jit_sum_b = jit_sum_b + abs_i(lat - last_lat_b[idx]);
                  jit_cnt_b = jit_cnt_b + 1;
                end
                last_lat_b[idx] = lat; have_last_b[idx] = 1;
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
    integer s, draw, i2;
    begin
      gen_b=0; del_b=0; overrun_b=0; err_b=0;
      gen_g=0; del_g=0; overrun_g=0; err_g=0;
      jit_sum_b=0; jit_cnt_b=0; jit_sum_g=0; jit_cnt_g=0;
      max_lat_b=0; max_lat_g=0;
      for (s=0;s<N;s=s+1) begin have_last_b[s]=0; have_last_g[s]=0; end
      score_b.init; score_g.init;
      for (i2=0;i2<total_cyc;i2=i2+1) begin
        for (s=0;s<N;s=s+1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw < bg_pct) begin
            if (score_b.qcount[s] == 0) begin
              gen_b = gen_b + 1; score_b.record_arrival(s, cyc);
            end else overrun_b = overrun_b + 1;
            if (score_g.qcount[s] == 0) begin
              gen_g = gen_g + 1; score_g.record_arrival(s, cyc);
            end else overrun_g = overrun_g + 1;
          end
        end
        for (s=0;s<N;s=s+1) begin
          req_base[s] = (score_b.qcount[s] > 0);
          req_gh[s]  = (score_g.qcount[s] > 0);
        end
        @(posedge clk); #1;
        drain_dut(valid0_b, row0_b, col_mask0_b, 0);
        drain_dut(valid1_b, row1_b, col_mask1_b, 0);
        drain_dut(valid0_g, row0_g, col_mask0_g, 1);
        drain_dut(valid1_g, row1_g, col_mask1_g, 1);
        cyc = cyc + 1;
      end
      req_base = 16'd0; req_gh = 16'd0;
      begin : tail
        integer s2, busy, guard;
        busy = 1; guard = 0;
        while (busy && guard < 100000) begin
          for (s2=0;s2<N;s2=s2+1) begin
            req_base[s2] = (score_b.qcount[s2] > 0);
            req_gh[s2] = (score_g.qcount[s2] > 0);
          end
          @(posedge clk); #1;
          drain_dut(valid0_b, row0_b, col_mask0_b, 0);
          drain_dut(valid1_b, row1_b, col_mask1_b, 0);
          drain_dut(valid0_g, row0_g, col_mask0_g, 1);
          drain_dut(valid1_g, row1_g, col_mask1_g, 1);
          cyc = cyc + 1; guard = guard + 1;
          busy = 0;
          for (s2=0;s2<N;s2=s2+1) if (score_b.qcount[s2]>0 || score_g.qcount[s2]>0) busy=1;
        end
      end
      total_err = total_err + err_b + err_g;
      $display("LOAD=%0d%% BASE: gen=%0d del=%0d overrun=%0d avg_jit=%0d.%0d max_lat=%0d | GLOBALHOLD(P=%0d): gen=%0d del=%0d overrun=%0d avg_jit=%0d.%0d max_lat=%0d",
        bg_pct, gen_b, del_b, overrun_b,
        (jit_cnt_b>0)?jit_sum_b/jit_cnt_b:0, (jit_cnt_b>0)?((jit_sum_b*10/jit_cnt_b)%10):0, max_lat_b,
        HOLD_PERIOD, gen_g, del_g, overrun_g,
        (jit_cnt_g>0)?jit_sum_g/jit_cnt_g:0, (jit_cnt_g>0)?((jit_sum_g*10/jit_cnt_g)%10):0, max_lat_g);
    end
  endtask

  initial begin
    rst = 1; req_base=16'd0; req_gh=16'd0; cyc=0; total_err=0;
    score_b.init; score_g.init;
    @(posedge clk); #1; rst = 0;

    run_load_point(3, 3000);
    run_load_point(15, 3000);
    run_load_point(30, 3000);
    run_load_point(50, 3000);
    run_load_point(75, 3000);
    run_load_point(100, 3000);

    if (total_err == 0)
      $display("GLOBALHOLD_VS_BASELINE_PASS");
    else
      $display("GLOBALHOLD_VS_BASELINE_FAIL total_err=%0d", total_err);
    $finish;
  end
endmodule
