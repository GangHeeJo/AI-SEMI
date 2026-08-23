// cluster2(round-robin, jitter 있음) vs cluster2_tdm(고정 시분할, jitter=0 기대)를
// 완전히 동일한 물리적 이벤트 스트림(소스별 발화 여부는 공유 RNG draw)으로 나란히
// 돌려서, jitter 개선과 처리량/손실 트레이드오프를 동시에 실측한다. 공용 하네스와
// 동일하게 소스당 1-entry(이미 pending이면 새 발화는 즉시 overrun) 모델 사용.
`timescale 1ns/1ps
module tb_cluster2_tdm_vs_baseline;
  parameter N = 16;
  parameter QDEPTH = 4;

  reg clk = 0;
  reg rst;
  reg [15:0] req_base, req_tdm;

  wire valid0_b; wire [1:0] row0_b; wire [3:0] col_mask0_b;
  wire valid1_b; wire [1:0] row1_b; wire [3:0] col_mask1_b;
  aer_tx16_trad_rowcol_fovea_cluster2 dut_base(
    .clk(clk), .rst(rst), .req(req_base),
    .valid0(valid0_b), .row0(row0_b), .col_mask0(col_mask0_b),
    .valid1(valid1_b), .row1(row1_b), .col_mask1(col_mask1_b));

  wire valid0_t; wire [1:0] row0_t; wire [3:0] col_mask0_t;
  wire valid1_t; wire [1:0] row1_t; wire [3:0] col_mask1_t;
  aer_tx16_trad_rowcol_fovea_cluster2_tdm dut_tdm(
    .clk(clk), .rst(rst), .req(req_tdm),
    .valid0(valid0_t), .row0(row0_t), .col_mask0(col_mask0_t),
    .valid1(valid1_t), .row1(row1_t), .col_mask1(col_mask1_t));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_b();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_t();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, c, idx, lat;
  integer gen_b, del_b, overrun_b, err_b;
  integer gen_t, del_t, overrun_t, err_t;
  integer total_err;

  integer last_lat_b [0:N-1]; integer have_last_b [0:N-1];
  integer last_lat_t [0:N-1]; integer have_last_t [0:N-1];
  integer jit_sum_b, jit_cnt_b, jit_sum_t, jit_cnt_t;

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
    input integer is_tdm;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (is_tdm) begin
              if (score_t.qcount[idx] <= 0) begin
                err_t = err_t + 1;
              end else begin
                lat = score_t.record_departure(idx, cyc);
                del_t = del_t + 1;
                if (have_last_t[idx]) begin
                  jit_sum_t = jit_sum_t + abs_i(lat - last_lat_t[idx]);
                  jit_cnt_t = jit_cnt_t + 1;
                end
                last_lat_t[idx] = lat; have_last_t[idx] = 1;
              end
            end else begin
              if (score_b.qcount[idx] <= 0) begin
                err_b = err_b + 1;
              end else begin
                lat = score_b.record_departure(idx, cyc);
                del_b = del_b + 1;
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
      gen_t=0; del_t=0; overrun_t=0; err_t=0;
      jit_sum_b=0; jit_cnt_b=0; jit_sum_t=0; jit_cnt_t=0;
      for (s=0;s<N;s=s+1) begin have_last_b[s]=0; have_last_t[s]=0; end
      score_b.init; score_t.init;
      for (i2=0;i2<total_cyc;i2=i2+1) begin
        for (s=0;s<N;s=s+1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw < bg_pct) begin
            if (score_b.qcount[s] == 0) begin
              gen_b = gen_b + 1; score_b.record_arrival(s, cyc);
            end else overrun_b = overrun_b + 1;
            if (score_t.qcount[s] == 0) begin
              gen_t = gen_t + 1; score_t.record_arrival(s, cyc);
            end else overrun_t = overrun_t + 1;
          end
        end
        for (s=0;s<N;s=s+1) begin
          req_base[s] = (score_b.qcount[s] > 0);
          req_tdm[s]  = (score_t.qcount[s] > 0);
        end
        @(posedge clk); #1;
        drain_dut(valid0_b, row0_b, col_mask0_b, 0);
        drain_dut(valid1_b, row1_b, col_mask1_b, 0);
        drain_dut(valid0_t, row0_t, col_mask0_t, 1);
        drain_dut(valid1_t, row1_t, col_mask1_t, 1);
        cyc = cyc + 1;
      end
      req_base = 16'd0; req_tdm = 16'd0;
      begin : tail
        integer s2, busy, guard;
        busy = 1; guard = 0;
        while (busy && guard < 100000) begin
          for (s2=0;s2<N;s2=s2+1) begin
            req_base[s2] = (score_b.qcount[s2] > 0);
            req_tdm[s2] = (score_t.qcount[s2] > 0);
          end
          @(posedge clk); #1;
          drain_dut(valid0_b, row0_b, col_mask0_b, 0);
          drain_dut(valid1_b, row1_b, col_mask1_b, 0);
          drain_dut(valid0_t, row0_t, col_mask0_t, 1);
          drain_dut(valid1_t, row1_t, col_mask1_t, 1);
          cyc = cyc + 1; guard = guard + 1;
          busy = 0;
          for (s2=0;s2<N;s2=s2+1) if (score_b.qcount[s2]>0 || score_t.qcount[s2]>0) busy=1;
        end
      end
      total_err = total_err + err_b + err_t;
      $display("LOAD=%0d%% BASE: gen=%0d del=%0d overrun=%0d avg_jit=%0d.%0d | TDM: gen=%0d del=%0d overrun=%0d avg_jit=%0d.%0d",
        bg_pct, gen_b, del_b, overrun_b,
        (jit_cnt_b>0)?jit_sum_b/jit_cnt_b:0, (jit_cnt_b>0)?((jit_sum_b*10/jit_cnt_b)%10):0,
        gen_t, del_t, overrun_t,
        (jit_cnt_t>0)?jit_sum_t/jit_cnt_t:0, (jit_cnt_t>0)?((jit_sum_t*10/jit_cnt_t)%10):0);
    end
  endtask

  initial begin
    rst = 1; req_base=16'd0; req_tdm=16'd0; cyc=0; total_err=0;
    score_b.init; score_t.init;
    @(posedge clk); #1; rst = 0;

    run_load_point(3, 3000);
    run_load_point(15, 3000);
    run_load_point(30, 3000);
    run_load_point(50, 3000);
    run_load_point(75, 3000);
    run_load_point(100, 3000);

    if (total_err == 0)
      $display("TDM_VS_BASELINE_PASS");
    else
      $display("TDM_VS_BASELINE_FAIL total_err=%0d", total_err);
    $finish;
  end
endmodule
