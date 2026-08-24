// cluster2_steal_buf_polarity 검증: (1) 원본 steal_buf와 주소/overrun 완전히 동일한지
// (극성 확장이 중재에 전혀 영향 없어야 함), (2) pol_mask가 실제 2-deep FIFO 순서(먼저 온
// 것부터 나감)를 정확히 반영하는지 -- §93의 event-ID FIFO와 구조가 같은, 극성 전용의
// 독립 소프트웨어 shadow FIFO를 오라클로 삼아 대조.
`timescale 1ns/1ps
module tb_steal_buf_polarity_correctness;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  reg [15:0] polarity_in;

  wire [15:0] ov_ref;
  wire vr0; wire [1:0] rr0; wire [3:0] cmr0;
  wire vr1; wire [1:0] rr1; wire [3:0] cmr1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf ref_dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(ov_ref),
    .valid0(vr0), .row0(rr0), .col_mask0(cmr0),
    .valid1(vr1), .row1(rr1), .col_mask1(cmr1));

  wire [15:0] ov;
  wire v0; wire [1:0] r0; wire [3:0] cm0; wire [3:0] pm0;
  wire v1; wire [1:0] r1; wire [3:0] cm1; wire [3:0] pm1;
  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(ov),
    .valid0(v0), .row0(r0), .col_mask0(cm0), .pol_mask0(pm0),
    .valid1(v1), .row1(r1), .col_mask1(cm1), .pol_mask1(pm1));

  always #5 clk = ~clk;

  integer i, c, cyc, addr_mismatch, pol_mismatch, checked_pol_bits, drain_until;
  reg [15:0] ov_sample, ov_ref_sample;
  reg [1:0] shadow_depth [0:15];
  reg pol_shadow0 [0:15];
  reg pol_shadow1 [0:15];

  task automatic shadow_check_grant(input integer valid_in, input integer row_in, input [3:0] mask_in, input [3:0] polmask_in);
    integer idx;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) if (mask_in[c]) begin
          idx = row_in*4 + c;
          checked_pol_bits = checked_pol_bits + 1;
          if (shadow_depth[idx] == 2'd0) begin
            $display("SHADOW_EMPTY_ON_GRANT idx=%0d cyc=%0d", idx, cyc);
          end else begin
            if (polmask_in[c] !== pol_shadow0[idx]) begin
              pol_mismatch = pol_mismatch + 1;
              $display("POL_FIFO_MISMATCH idx=%0d cyc=%0d got=%b want=%b", idx, cyc, polmask_in[c], pol_shadow0[idx]);
            end
            pol_shadow0[idx] = pol_shadow1[idx];
            shadow_depth[idx] = shadow_depth[idx] - 2'd1;
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    addr_mismatch = 0; pol_mismatch = 0; checked_pol_bits = 0;
    for (i = 0; i < 16; i = i + 1) begin
      shadow_depth[i] = 2'd0; pol_shadow0[i] = 1'b0; pol_shadow1[i] = 1'b0;
    end
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < 30000; cyc = cyc + 1) begin
      arrival = $random;
      polarity_in = $random;
      #1;
      ov_sample = ov; ov_ref_sample = ov_ref; // overrun은 순수 조합논리(arrival & pending_full,
                      // pre-edge 상태) -- 반드시 이 엣지 전에 샘플링해야 함(엣지 후엔
                      // pending_full이 이미 갱신돼 있어서 arrival과 조합이 안 맞음)

      if (ov_sample !== ov_ref_sample) begin
        addr_mismatch = addr_mismatch + 1;
        $display("OVERRUN_MISMATCH cyc=%0d", cyc);
      end

      @(posedge clk); #1;

      if (v0 !== vr0 || r0 !== rr0 || cm0 !== cmr0 ||
          v1 !== vr1 || r1 !== rr1 || cm1 !== cmr1) begin
        addr_mismatch = addr_mismatch + 1;
        $display("ADDR_MISMATCH cyc=%0d", cyc);
      end

      shadow_check_grant(v0, r0, cm0, pm0);
      shadow_check_grant(v1, r1, cm1, pm1);

      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && !ov_sample[i]) begin
          if (shadow_depth[i] == 2'd0) pol_shadow0[i] = polarity_in[i];
          else pol_shadow1[i] = polarity_in[i];
          shadow_depth[i] = shadow_depth[i] + 2'd1;
        end
      end
    end

    // drain: 남은 shadow 전부 비워질 때까지
    arrival = 16'd0; polarity_in = 16'd0;
    drain_until = cyc + 15000;
    for (cyc = cyc; cyc < drain_until; cyc = cyc + 1) begin
      @(posedge clk); #1;
      if (v0 !== vr0 || r0 !== rr0 || cm0 !== cmr0 ||
          v1 !== vr1 || r1 !== rr1 || cm1 !== cmr1) begin
        addr_mismatch = addr_mismatch + 1;
        $display("ADDR_MISMATCH(drain) cyc=%0d", cyc);
      end
      shadow_check_grant(v0, r0, cm0, pm0);
      shadow_check_grant(v1, r1, cm1, pm1);
    end

    for (i = 0; i < 16; i = i + 1) if (shadow_depth[i] != 0) begin
      $display("DRAIN_INCOMPLETE idx=%0d depth=%0d", i, shadow_depth[i]);
      pol_mismatch = pol_mismatch + 1;
    end

    $display("checked_pol_bits=%0d addr_mismatch=%0d pol_mismatch=%0d", checked_pol_bits, addr_mismatch, pol_mismatch);
    if (addr_mismatch == 0 && pol_mismatch == 0) $display("STEAL_BUF_POLARITY_PASS");
    else $display("STEAL_BUF_POLARITY_FAIL");
    $finish;
  end
endmodule
