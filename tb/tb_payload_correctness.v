// payload 멀티플렉서 배선 검증 -- data_in[i]=i로 고정해두면, valid일 때 항상
// data_out==addr이어야 함(각 소스의 페이로드를 그 소스 번호로 마킹해뒀으니까,
// 멀티플렉서가 엉뚱한 소스 데이터를 골랐으면 바로 불일치가 남).
`timescale 1ns/1ps
module tb_payload_correctness;
  parameter DATA_WIDTH = 16;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [16*DATA_WIDTH-1:0] data_in;
  wire valid; wire [3:0] addr; wire [DATA_WIDTH-1:0] data_out;

  aer_tx16_trad_rowcol_fovea_payload #(.WEIGHT(5), .DATA_WIDTH(DATA_WIDTH)) dut(
    .clk(clk), .rst(rst), .req(req), .data_in(data_in),
    .valid(valid), .addr(addr), .data_out(data_out));

  always #5 clk = ~clk;
  integer i, cyc, draw, mismatch;
  integer rng_seed = 1;

  initial begin
    for (i = 0; i < 16; i = i + 1)
      data_in[i*DATA_WIDTH +: DATA_WIDTH] = i[DATA_WIDTH-1:0];
    mismatch = 0;
    rst = 1; req = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < 20) req[i] = 1'b1;
      end
      @(posedge clk); #1;
      if (valid) begin
        req[addr] = 1'b0; // 이번에 서비스된 소스는 요청 내림(다음 도착 전까지)
        if (data_out !== addr) begin
          mismatch = mismatch + 1;
          $display("MISMATCH cyc=%0d addr=%0d data_out=%0d", cyc, addr, data_out);
        end
      end
    end

    $display("mismatch=%0d", mismatch);
    if (mismatch == 0) $display("PAYLOAD_MUX_PASS");
    else $display("PAYLOAD_MUX_FAIL");
    $finish;
  end
endmodule
