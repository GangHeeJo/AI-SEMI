// cluster2_polarity가 (1) 원본 cluster2와 valid/row/col_mask가 완전히 동일하고(극성
// 추가가 주소 중재에 전혀 영향 안 줌), (2) pol_mask가 이긴 열들의 polarity_in을 정확히
// 반영하는지를 무작위 실코어 20,000사이클로 검증.
`timescale 1ns/1ps
module tb_cluster2_polarity_correctness;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [15:0] polarity_in;

  wire v0_ref; wire [1:0] r0_ref; wire [3:0] cm0_ref;
  wire v1_ref; wire [1:0] r1_ref; wire [3:0] cm1_ref;
  aer_tx16_trad_rowcol_fovea_cluster2 ref_dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(v0_ref), .row0(r0_ref), .col_mask0(cm0_ref),
    .valid1(v1_ref), .row1(r1_ref), .col_mask1(cm1_ref));

  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;
  aer_tx16_trad_rowcol_fovea_cluster2_polarity dut(
    .clk(clk), .rst(rst), .req(req), .polarity_in(polarity_in),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer i, cyc, mismatch, pol_mismatch, checked_pol_bits;
  reg [15:0] req_q, pol_q; // 1사이클 지연된 입력(출력이 등록되므로 비교 시점에 필요)
  reg [3:0] expect_pol0, expect_pol1;

  function [3:0] rowbits4;
    input [15:0] v16; input [1:0] r;
    begin
      case (r)
        2'd0: rowbits4 = v16[3:0];
        2'd1: rowbits4 = v16[7:4];
        2'd2: rowbits4 = v16[11:8];
        default: rowbits4 = v16[15:12];
      endcase
    end
  endfunction

  initial begin
    rst = 1; req = 16'd0; polarity_in = 16'd0; req_q = 16'd0; pol_q = 16'd0;
    mismatch = 0; pol_mismatch = 0; checked_pol_bits = 0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      req = $random;
      polarity_in = $random;
      @(posedge clk); #1;

      if (v0 !== v0_ref || r0 !== r0_ref || cm0 !== cm0_ref ||
          v1 !== v1_ref || r1 !== r1_ref || cm1 !== cm1_ref) begin
        mismatch = mismatch + 1;
        $display("ARBITRATION_MISMATCH cyc=%0d", cyc);
      end

      expect_pol0 = rowbits4(polarity_in, r0);
      expect_pol1 = rowbits4(polarity_in, r1);
      if (v0) begin
        for (i = 0; i < 4; i = i + 1) if (cm0[i]) begin
          checked_pol_bits = checked_pol_bits + 1;
          if (pm0[i] !== expect_pol0[i]) begin
            pol_mismatch = pol_mismatch + 1;
            $display("POL_MISMATCH lane0 cyc=%0d col=%0d", cyc, i);
          end
        end
      end
      if (v1) begin
        for (i = 0; i < 4; i = i + 1) if (cm1[i]) begin
          checked_pol_bits = checked_pol_bits + 1;
          if (pm1[i] !== expect_pol1[i]) begin
            pol_mismatch = pol_mismatch + 1;
            $display("POL_MISMATCH lane1 cyc=%0d col=%0d", cyc, i);
          end
        end
      end
    end

    $display("cycles=20000 checked_pol_bits=%0d arbitration_mismatch=%0d pol_mismatch=%0d",
      checked_pol_bits, mismatch, pol_mismatch);
    if (mismatch == 0 && pol_mismatch == 0) $display("POLARITY_CORRECTNESS_PASS");
    else $display("POLARITY_CORRECTNESS_FAIL");
    $finish;
  end
endmodule
