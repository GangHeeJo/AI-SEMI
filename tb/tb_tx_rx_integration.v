// TX(cluster2_steal_buf)+RX(aer_rx16_steal_buf) 통합 검증 -- RX가 복원한
// source_valid가 TX의 row/col_mask를 정확히 반영하는지(디코드 자체의 정확성) +
// 소스별로 "도착-overrun" 총량과 RX에서 받은 총량이 일치하는지(전체 배관 확인).
`timescale 1ns/1ps
module tb_tx_rx_integration;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 15;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;
  wire [15:0] source_valid;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf tx(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  aer_rx16_steal_buf rx(
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1),
    .source_valid(source_valid));

  always #5 clk = ~clk;

  integer rng_seed = 51;
  integer cyc, i, draw, error_count;
  integer generated [0:15];
  integer received [0:15];
  integer dropped [0:15];

  function integer popcount16;
    input [15:0] v;
    integer j;
    begin
      popcount16 = 0;
      for (j = 0; j < 16; j = j + 1) popcount16 = popcount16 + v[j];
    end
  endfunction

  initial begin
    rst = 1; arrival = 16'd0; error_count = 0;
    for (i = 0; i < 16; i = i + 1) begin generated[i]=0; received[i]=0; dropped[i]=0; end
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival = 16'd0;
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated[i] = generated[i] + 1;
          arrival[i] = 1'b1;
        end
      end
      #1;
      for (i = 0; i < 16; i = i + 1) if (overrun_w[i]) dropped[i] = dropped[i] + 1;

      @(posedge clk); #1;
      // RX 디코드 정확성: source_valid가 TX의 row/col_mask 원본과 정확히 일치하는지
      // 직접 재계산해서 대조(RX를 안 믿고 다시 계산).
      if (source_valid !== (((valid0 ? (col_mask0 << (row0*4)) : 16'd0)) |
                             ((valid1 ? (col_mask1 << (row1*4)) : 16'd0)))) begin
        error_count = error_count + 1;
        $display("RX_DECODE_MISMATCH cyc=%0d source_valid=%b", cyc, source_valid);
      end
      for (i = 0; i < 16; i = i + 1) if (source_valid[i]) received[i] = received[i] + 1;
    end

    // drain
    arrival = 16'd0;
    for (cyc = CYCLES; cyc < CYCLES + 500; cyc = cyc + 1) begin
      @(posedge clk); #1;
      for (i = 0; i < 16; i = i + 1) if (source_valid[i]) received[i] = received[i] + 1;
    end

    for (i = 0; i < 16; i = i + 1) begin
      if ((received[i] + dropped[i]) != generated[i]) begin
        error_count = error_count + 1;
        $display("SRC_MISMATCH src=%0d generated=%0d received=%0d dropped=%0d",
          i, generated[i], received[i], dropped[i]);
      end
    end

    if (error_count == 0) $display("TX_RX_INTEGRATION_PASS");
    else $display("TX_RX_INTEGRATION_FAIL errors=%0d", error_count);
    $finish;
  end
endmodule
