// v2(full+grant 동시수락)를 (1) 무작위 실코어로 v1(원본)과 나란히 구동해 overrun이
// v1보다 적거나 같은지 + 극성 순서가 여전히 정확한지, (2) 독립 소프트웨어 shadow FIFO
// 오라클(v2와 같은 bypass 규칙 구현)과 대조해 검증.
`timescale 1ns/1ps
module tb_steal_buf_polarity_v2_correctness;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;

  wire [15:0] ov1;
  wire v0_1; wire [1:0] r0_1; wire [3:0] cm0_1; wire [3:0] pm0_1;
  wire v1_1; wire [1:0] r1_1; wire [3:0] cm1_1; wire [3:0] pm1_1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity dut_v1(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov1),
    .valid0(v0_1), .row0(r0_1), .col_mask0(cm0_1), .pol_mask0(pm0_1),
    .valid1(v1_1), .row1(r1_1), .col_mask1(cm1_1), .pol_mask1(pm1_1));

  wire [15:0] ov2;
  wire v0_2; wire [1:0] r0_2; wire [3:0] cm0_2; wire [3:0] pm0_2;
  wire v1_2; wire [1:0] r1_2; wire [3:0] cm1_2; wire [3:0] pm1_2;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_v2 dut_v2(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov2),
    .valid0(v0_2), .row0(r0_2), .col_mask0(cm0_2), .pol_mask0(pm0_2),
    .valid1(v1_2), .row1(r1_2), .col_mask1(cm1_2), .pol_mask1(pm1_2));

  always #5 clk = ~clk;

  integer i, c, cyc, pol_mismatch, checked_pol_bits, order_violation;
  integer overrun_v1_total, overrun_v2_total;
  reg [15:0] ov1_sample, ov2_sample;

  // v2 규칙을 그대로 구현한 소프트웨어 shadow FIFO (v2 DUT의 pol_mask 오라클)
  reg [1:0] shadow_depth [0:15];
  reg pol_shadow0 [0:15];
  reg pol_shadow1 [0:15];
  reg [15:0] granted2_sample; // 이번 사이클 v2가 실제로 grant한 소스 비트맵(오라클 갱신용)

  task automatic shadow_check_grant(input integer valid_in, input integer row_in, input [3:0] mask_in, input [3:0] polmask_in);
    integer idx;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) if (mask_in[c]) begin
          idx = row_in*4 + c;
          checked_pol_bits = checked_pol_bits + 1;
          granted2_sample[idx] = 1'b1;
          if (shadow_depth[idx] == 2'd0) begin
            $display("SHADOW_EMPTY_ON_GRANT idx=%0d cyc=%0d", idx, cyc);
          end else if (polmask_in[c] !== pol_shadow0[idx]) begin
            pol_mismatch = pol_mismatch + 1;
            $display("POL_FIFO_MISMATCH idx=%0d cyc=%0d got=%b want=%b", idx, cyc, polmask_in[c], pol_shadow0[idx]);
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    pol_mismatch = 0; checked_pol_bits = 0; order_violation = 0;
    overrun_v1_total = 0; overrun_v2_total = 0;
    for (i = 0; i < 16; i = i + 1) begin
      shadow_depth[i] = 2'd0; pol_shadow0[i] = 1'b0; pol_shadow1[i] = 1'b0;
    end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      arrival = $random;
      polarity_in = $random;
      #1;
      ov1_sample = ov1; ov2_sample = ov2;
      overrun_v1_total = overrun_v1_total + $countones(ov1_sample);
      overrun_v2_total = overrun_v2_total + $countones(ov2_sample);
      // v1/v2는 30,000사이클 동안 완전히 독립적으로 도는 두 stateful DUT라서(같은
      // arrival/polarity_in을 받아도 admission 이력이 갈라지므로) "이번 사이클에 어느
      // 쪽이 overrun났나"는 각 DUT의 누적 상태에 달려있어 직접 비교 대상이 아님 --
      // 총 overrun 개수(overrun_v1_total vs overrun_v2_total)만 유의미한 비교 지표.

      granted2_sample = 16'd0;

      @(posedge clk); #1;

      shadow_check_grant(v0_2, r0_2, cm0_2, pm0_2);
      shadow_check_grant(v1_2, r1_2, cm1_2, pm1_2);

      // shadow FIFO 갱신: v2와 같은 bypass 규칙(soft 모델)
      for (i = 0; i < 16; i = i + 1) begin
        if (granted2_sample[i]) begin
          if (shadow_depth[i] == 2'd2) begin
            pol_shadow0[i] = pol_shadow1[i];
            if (arrival[i] && !ov2_sample[i]) begin
              pol_shadow1[i] = polarity_in[i];
              // depth 그대로 2
            end else shadow_depth[i] = 2'd1;
          end else begin // old depth == 1
            if (arrival[i] && !ov2_sample[i]) begin
              pol_shadow0[i] = polarity_in[i];
              // depth 그대로 1
            end else shadow_depth[i] = 2'd0;
          end
        end else begin
          if (arrival[i] && !ov2_sample[i]) begin
            if (shadow_depth[i] == 2'd0) pol_shadow0[i] = polarity_in[i];
            else pol_shadow1[i] = polarity_in[i];
            shadow_depth[i] = shadow_depth[i] + 2'd1;
          end
        end
      end
    end

    $display("cycles=30000 checked_pol_bits=%0d pol_mismatch=%0d overrun_v1=%0d overrun_v2=%0d improvement=%0d",
      checked_pol_bits, pol_mismatch, overrun_v1_total, overrun_v2_total, overrun_v1_total - overrun_v2_total);
    if (pol_mismatch == 0 && overrun_v2_total < overrun_v1_total) $display("STEAL_BUF_POLARITY_V2_CORRECTNESS_PASS");
    else $display("STEAL_BUF_POLARITY_V2_CORRECTNESS_FAIL");
    $finish;
  end
endmodule
