// shadow_cnt 배열 대신, RTL 내부 pending_gt0가 drain 후 정말 0이 되는지 + 원시
// 이벤트 카운트(생성-overrun-배출=0)만으로 단순하게 재검증. shadow 모델의 버그
// 가능성을 배제하기 위한 독립적인 확인.
`timescale 1ns/1ps
module tb_steal_buf_raw_count;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer rng_seed = 41; // 원래 테스트와 동일 시드로 같은 자극 재현
  integer cyc, i, draw;
  integer generated, dropped_overrun, delivered_raw;

  function integer popcount4;
    input [3:0] v;
    begin
      popcount4 = v[0]+v[1]+v[2]+v[3];
    end
  endfunction

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; dropped_overrun = 0; delivered_raw = 0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          arrival[i] = 1'b1;
        end
      end
      #1;
      for (i = 0; i < 16; i = i + 1) if (overrun_w[i]) dropped_overrun = dropped_overrun + 1;
      @(posedge clk); #1;
      if (valid0) delivered_raw = delivered_raw + popcount4(col_mask0);
      if (valid1) delivered_raw = delivered_raw + popcount4(col_mask1);
    end

    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + 500; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (valid0) delivered_raw = delivered_raw + popcount4(col_mask0);
      if (valid1) delivered_raw = delivered_raw + popcount4(col_mask1);
    end

    $display("generated=%0d dropped_overrun=%0d delivered_raw=%0d sum=%0d final_pending_gt0=%b",
      generated, dropped_overrun, delivered_raw, dropped_overrun+delivered_raw, dut.pending_gt0);
    if ((dropped_overrun + delivered_raw) == generated && dut.pending_gt0 == 16'd0)
      $display("RAW_COUNT_PASS");
    else
      $display("RAW_COUNT_FAIL");
    $finish;
  end
endmodule
