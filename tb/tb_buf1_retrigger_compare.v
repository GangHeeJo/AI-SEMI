// 1-deep(cluster_buf1) vs 2-deep(cluster_buf) 재발화 비교. tb_buf_retrigger_compare.v와
// 같은 넌블로킹 레이스 재현 패턴, cluster_buf1 쪽만 추가.
`timescale 1ns/1ps
module tb_buf1_retrigger_compare;
  parameter CYCLES = 256;

  reg clk = 0;
  reg rst;

  reg [15:0] arrival_buf1;
  wire [15:0] overrun_buf1_w;
  wire valid_buf1; wire [1:0] row_buf1; wire [3:0] colmask_buf1;
  aer_tx16_trad_rowcol_fovea_cluster_buf1 #(.WEIGHT(5)) tx_buf1(
    .clk(clk), .rst(rst), .arrival(arrival_buf1), .overrun(overrun_buf1_w),
    .valid(valid_buf1), .row(row_buf1), .col_mask(colmask_buf1));
  integer overrun_buf1, generated_buf1, delivered_buf1;

  always #5 clk = ~clk;

  integer cyc_buf1;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      generated_buf1 <= 0; overrun_buf1 <= 0; delivered_buf1 <= 0; cyc_buf1 <= 0; arrival_buf1 <= 16'd0;
    end else begin
      if (cyc_buf1 < CYCLES) begin
        generated_buf1 <= generated_buf1 + 1;
        arrival_buf1 <= 16'd1;
        cyc_buf1 <= cyc_buf1 + 1;
      end else begin
        arrival_buf1 <= 16'd0;
      end
      if (overrun_buf1_w[0]) overrun_buf1 <= overrun_buf1 + 1;
      if (valid_buf1 && (row_buf1 == 2'd0) && colmask_buf1[0]) delivered_buf1 <= delivered_buf1 + 1;
    end
  end

  initial begin
    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
    wait (cyc_buf1 >= CYCLES);
    repeat (10) @(posedge clk);
    $display("[cluster_buf1(1-deep)] generated=%0d overrun=%0d delivered=%0d", generated_buf1, overrun_buf1, delivered_buf1);
    $finish;
  end
endmodule
