// 1번(주소 오버헤드) -- N(배열 크기)을 스윕하면서 cluster2류(주소기반) vs
// dense bitmap(위치기반)의 비트비용 손익분기점이 어떻게 이동하는지 확인.
// cluster2의 핵심 구조(2레인, 그랜트당 최대 4열 묶음, 소스당 1-entry)는 그대로
// 유지하고 N만 일반화(행 개수=N/4, 레인당 N/8행) -- arbiter/RTL 재설계 없이
// 동작모델(behavioral)로 캡처. 레인 내 행 선택은 "가장 낮은 인덱스의 요청중인 행"
// (공정성 시험이 아니라 용량/비트비용 시험이라 단순화, 결과에 영향 없음).
`timescale 1ns/1ps
module tb_bitcost_scale_sweep;
  parameter integer NMAX = 256;

  integer rng_seed = 1;
  integer cyc, s;
  integer generated_a, delivered_a, overrun_a, addr_bits;
  integer generated_b, delivered_b, overrun_b, bitmap_bits;

  reg [NMAX-1:0] pending_a, pending_b;
  integer N, ROWS, ROWS_PER_LANE, ADDR_BITS_PER_GRANT;

  function automatic integer clog2;
    input integer value;
    integer v, r;
    begin
      v = value - 1; r = 0;
      while (v > 0) begin
        v = v >> 1; r = r + 1;
      end
      clog2 = r;
    end
  endfunction

  // 레인 하나: 자기 담당 행 범위(row_lo..row_hi) 중 가장 낮은 인덱스로 요청중인
  // 행을 골라, 그 행의 4열을 전부(현재 pending인 것만) 서비스. 그랜트 있었으면
  // ADDR_BITS_PER_GRANT만큼 비용 발생.
  task automatic service_lane;
    input integer row_lo;
    input integer row_hi;
    integer r, c, idx, found_row, has_any;
    begin
      found_row = -1;
      for (r = row_lo; r <= row_hi; r = r + 1) begin
        has_any = 0;
        for (c = 0; c < 4; c = c + 1) begin
          idx = r*4 + c;
          if (pending_a[idx]) has_any = 1;
        end
        if (has_any && found_row < 0) found_row = r;
      end
      if (found_row >= 0) begin
        addr_bits = addr_bits + ADDR_BITS_PER_GRANT;
        for (c = 0; c < 4; c = c + 1) begin
          idx = found_row*4 + c;
          if (pending_a[idx]) begin
            pending_a[idx] = 1'b0;
            delivered_a = delivered_a + 1;
          end
        end
      end
    end
  endtask

  task automatic run_load_point;
    input integer bg_pct;
    input integer total_cyc;
    integer draw;
    begin
      generated_a=0; delivered_a=0; overrun_a=0; addr_bits=0;
      generated_b=0; delivered_b=0; overrun_b=0; bitmap_bits=0;
      pending_a = {NMAX{1'b0}}; pending_b = {NMAX{1'b0}};
      for (cyc = 0; cyc < total_cyc; cyc = cyc + 1) begin
        for (s = 0; s < N; s = s + 1) begin
          draw = (($random(rng_seed)%100+100)%100);
          if (draw < bg_pct) begin
            if (!pending_a[s]) begin generated_a = generated_a+1; pending_a[s]=1'b1; end
            else overrun_a = overrun_a + 1;
            if (!pending_b[s]) begin generated_b = generated_b+1; pending_b[s]=1'b1; end
            else overrun_b = overrun_b + 1;
          end
        end
        // addressed: 레인0=행 0..ROWS_PER_LANE-1, 레인1=나머지
        service_lane(0, ROWS_PER_LANE-1);
        service_lane(ROWS_PER_LANE, ROWS-1);
        // bitmap: 매 사이클 고정 N비트, pending 전부 즉시 서비스(무제한 용량)
        bitmap_bits = bitmap_bits + N;
        for (s = 0; s < N; s = s + 1) begin
          if (pending_b[s]) begin pending_b[s] = 1'b0; delivered_b = delivered_b + 1; end
        end
      end
      $display("N=%0d LOAD=%0d%% ADDR: gen=%0d del=%0d overrun=%0d bits=%0d bits/ev=%0d.%0d | BITMAP: gen=%0d del=%0d overrun=%0d bits=%0d bits/ev=%0d.%0d",
        N, bg_pct, generated_a, delivered_a, overrun_a, addr_bits,
        (delivered_a>0)?addr_bits/delivered_a:0, (delivered_a>0)?((addr_bits*10/delivered_a)%10):0,
        generated_b, delivered_b, overrun_b, bitmap_bits,
        (delivered_b>0)?bitmap_bits/delivered_b:0, (delivered_b>0)?((bitmap_bits*10/delivered_b)%10):0);
    end
  endtask

  task automatic run_n;
    input integer n_val;
    begin
      N = n_val;
      ROWS = N/4;
      ROWS_PER_LANE = ROWS/2;
      ADDR_BITS_PER_GRANT = clog2(ROWS) + 4;
      $display("--- N=%0d (ROWS=%0d, addr_bits_per_grant=%0d) ---", N, ROWS, ADDR_BITS_PER_GRANT);
      run_load_point(3, 2000);
      run_load_point(15, 2000);
      run_load_point(30, 2000);
      run_load_point(50, 2000);
      run_load_point(75, 2000);
      run_load_point(100, 2000);
    end
  endtask

  initial begin
    run_n(16);
    run_n(64);
    run_n(256);
    $display("SCALE_SWEEP_DONE");
    $finish;
  end
endmodule
