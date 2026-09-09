`timescale 1ns/1ps
// aer_tx16_coord_transform_v1 무작위 스트레스 검증 -- 실트래픽(UZH)만으로는 world_mem_writer의
// 같은 사이클 레인 충돌 정책(§world_mem_writer.v)이 거의 안 걸린다(실측 87/4096칸, 충돌 희소).
// 로컬(row,col)+theta_idx 조합 중 실제로 서로 다른(row,col)이 같은 world (X,Y)로 겹치는
// 경우가 존재함을 오라클로 확인했으므로(scripts/coord_transform_model.py, 284/256 theta에서
// 발생), 여기서는 높은 도착률(20%/source) + 매 사이클 무작위 theta로 그 충돌 경로를 실제로
// 반복 자극해서 world_mem_writer의 "레인 인덱스 큰 쪽이 이긴다" 정책이 shadow와 항상
// 일치하는지 본다. 검증 방법은 tb_aer_tx16_coord_transform_v1_uzh_trace.v와 완전히 동일
// (계층참조로 steal_buf 배출 관찰 -> coord_transform_rmcm_lut로 기대값 계산 -> 최종 rd 포트
// 전수 비교).
module tb_aer_tx16_coord_transform_v1_correctness;
  `include "rtl/coord_transform_rmcm_lut.vh"

  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  reg [7:0]  theta_idx;
  wire [15:0] overrun;
  reg         rd_en;
  reg  [5:0]  rd_x, rd_y;
  wire        rd_written, rd_pol;

  aer_tx16_coord_transform_v1 dut (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx),
    .overrun(overrun),
    .rd_en(rd_en), .rd_x(rd_x), .rd_y(rd_y),
    .rd_written(rd_written), .rd_pol(rd_pol)
  );

  always #5 clk = ~clk;

  reg shadow_written [0:4095];
  reg shadow_pol     [0:4095];

  task automatic shadow_write(input [1:0] row, input [1:0] col, input pol, input [7:0] th);
    reg [11:0] xy;
    reg [5:0] X, Y;
    integer addr;
    begin
      xy  = coord_transform_rmcm_lut(row, col, th);
      X = xy[11:6]; Y = xy[5:0];
      addr = Y*64 + X;
      shadow_written[addr] = 1'b1;
      shadow_pol[addr] = pol;
    end
  endtask

  // coord_transform_rmcm이 등록형이라 실제 latch되는 theta는 "다음" edge 시점 값이다
  // (tb_aer_tx16_coord_transform_v1_uzh_trace.v와 동일한 이유) -- theta_next를 인자로 받는다.
  task automatic shadow_check_cycle(input [7:0] theta_next);
    integer c;
    begin
      if (dut.u_tx.valid0)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask0[c]) shadow_write(dut.u_tx.row0, c[1:0], dut.u_tx.pol_mask0[c], theta_next);
      if (dut.u_tx.valid1)
        for (c = 0; c < 4; c = c + 1)
          if (dut.u_tx.col_mask1[c]) shadow_write(dut.u_tx.row1, c[1:0], dut.u_tx.pol_mask1[c], theta_next);
    end
  endtask

  integer i, cyc;
  integer N_CYCLES;
  reg [7:0] th_pending;

  initial begin
    N_CYCLES = 20000;
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx = 8'd0;
    rd_en = 0; rd_x = 0; rd_y = 0;
    for (i = 0; i < 4096; i = i + 1) begin shadow_written[i] = 1'b0; shadow_pol[i] = 1'b0; end

    @(posedge clk); #1; rst = 0;

    // theta_idx는 매 edge 직후(#1 뒤) 곧바로 다음 값으로 갱신되므로, coord_transform_rmcm이
    // "이번에 보이는 col_mask0"와 함께 실제로 latch하는 theta는 이번 반복에서 미리 정한 값이
    // 아니라 "edge 직후 새로 뽑는" 값이다(tb_..._uzh_trace.v의 theta_by_cyc[cyc+1]과 같은
    // 이유) -- th_pending으로 한 박자 미리 큐잉해서 순서를 맞춘다.
    th_pending = $random;
    for (cyc = 0; cyc < N_CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0; polarity_in = $random;
      for (i = 0; i < 16; i = i + 1)
        if (($random % 100) < 20) arrival[i] = 1'b1;
      theta_idx = th_pending;
      @(posedge clk); #1;
      th_pending = $random;
      shadow_check_cycle(th_pending);
    end

    // drain -- pending_cnt가 최대 2-deep이라 짧은 마무리로 충분
    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 10; i = i + 1) begin
      theta_idx = th_pending;
      @(posedge clk); #1;
      th_pending = $random;
      shadow_check_cycle(th_pending);
    end

    begin : COMPARE
      integer x, y, addr, mismatches, filled_rtl, filled_shadow;
      mismatches = 0; filled_rtl = 0; filled_shadow = 0;
      for (y = 0; y < 64; y = y + 1) begin
        for (x = 0; x < 64; x = x + 1) begin
          rd_en = 1; rd_x = x[5:0]; rd_y = y[5:0];
          @(posedge clk); #1;
          addr = y*64 + x;
          if (shadow_written[addr]) filled_shadow = filled_shadow + 1;
          if (rd_written) filled_rtl = filled_rtl + 1;
          if (rd_written !== shadow_written[addr] ||
              (shadow_written[addr] && rd_pol !== shadow_pol[addr])) begin
            mismatches = mismatches + 1;
            if (mismatches <= 10)
              $display("MISMATCH x=%0d y=%0d rtl(written=%b pol=%b) shadow(written=%b pol=%b)",
                        x, y, rd_written, rd_pol, shadow_written[addr], shadow_pol[addr]);
          end
        end
      end
      $display("N_CYCLES=%0d filled_rtl=%0d/4096 filled_shadow=%0d/4096 mismatches=%0d",
                N_CYCLES, filled_rtl, filled_shadow, mismatches);
      if (mismatches == 0)
        $display("AER_TX16_COORD_TRANSFORM_V1_CORRECTNESS_PASS");
      else
        $display("AER_TX16_COORD_TRANSFORM_V1_CORRECTNESS_FAIL");
    end
    $finish;
  end
endmodule
