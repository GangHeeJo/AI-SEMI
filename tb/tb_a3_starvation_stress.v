// §64 스트레스 테스트를 준영의 A3(exact scalar prefix) RTL에 그대로 적용.
// 중심(row1,2=source4~11)은 항상 포화(매 사이클 전부 pending), 주변(row0,3=
// source0~3,12~15)은 ARRIVAL_PCT(기본 3%)로 희소하게 도착 -- cluster2_dynamic
// (§64, 우리 팀이 기각한 top-2 전역선택)과 같은 굶주림이 A3에도 나타나는지 확인.
`timescale 1ns/1ps
module tb_a3_starvation_stress;
  parameter CYCLES = 20000;
  parameter ARRIVAL_PCT = 3;

  reg clk = 0;
  reg rst;
  reg [15:0] source_pending;
  wire [1:0] grant_count;
  wire [3:0] lane0_addr, lane1_addr;
  reg bundle_ready;

  a3_exact_scalar_prefix_k2 dut(
    .clk(clk), .rst(rst),
    .source_pending(source_pending),
    .grant_count(grant_count),
    .lane0_addr(lane0_addr),
    .lane1_addr(lane1_addr),
    .bundle_ready(bundle_ready));

  always #5 clk = ~clk;

  integer rng_seed = 7;
  integer cyc, i, draw;
  reg [15:0] periph_pending;      // 실제 admission 추적(주변만)
  integer periph_generated, periph_delivered, periph_overrun;
  integer center_delivered;
  integer total_delivered;

  task automatic apply_grants;
    begin
      if (grant_count >= 2'd1) begin
        if (lane0_addr[3:2] == 2'd1 || lane0_addr[3:2] == 2'd2)
          center_delivered = center_delivered + 1;
        else begin
          if (periph_pending[lane0_addr]) begin
            periph_pending[lane0_addr] = 1'b0;
            periph_delivered = periph_delivered + 1;
          end
        end
        total_delivered = total_delivered + 1;
      end
      if (grant_count == 2'd2) begin
        if (lane1_addr[3:2] == 2'd1 || lane1_addr[3:2] == 2'd2)
          center_delivered = center_delivered + 1;
        else begin
          if (periph_pending[lane1_addr]) begin
            periph_pending[lane1_addr] = 1'b0;
            periph_delivered = periph_delivered + 1;
          end
        end
        total_delivered = total_delivered + 1;
      end
    end
  endtask

  initial begin
    rst = 1; source_pending = 16'd0; bundle_ready = 1'b1;
    periph_pending = 16'd0;
    periph_generated=0; periph_delivered=0; periph_overrun=0;
    center_delivered=0; total_delivered=0;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      // 주변(행0,3=source0~3,12~15) 희소 도착, 소스당 1-entry
      for (i = 0; i < 4; i = i + 1) begin
        draw = (($random(rng_seed)%100+100)%100);
        if (draw < ARRIVAL_PCT) begin
          if (periph_pending[i]) periph_overrun = periph_overrun + 1;
          else begin periph_pending[i] = 1'b1; periph_generated = periph_generated + 1; end
        end
      end
      for (i = 12; i < 16; i = i + 1) begin
        draw = (($random(rng_seed)%100+100)%100);
        if (draw < ARRIVAL_PCT) begin
          if (periph_pending[i]) periph_overrun = periph_overrun + 1;
          else begin periph_pending[i] = 1'b1; periph_generated = periph_generated + 1; end
        end
      end
      // 중심(행1,2=source4~11) 항상 포화
      source_pending = periph_pending | 16'h0FF0;
      apply_grants;
      @(posedge clk); #1;
    end

    $display("CENTER: delivered=%0d", center_delivered);
    $display("PERIPH: generated=%0d delivered=%0d overrun=%0d survival=%0d.%0d%%",
      periph_generated, periph_delivered, periph_overrun,
      (periph_generated>0)?(periph_delivered*100)/periph_generated:0,
      (periph_generated>0)?((periph_delivered*1000)/periph_generated)%10:0);
    $display("TOTAL delivered=%0d (center_share=%0d.%0d%%)", total_delivered,
      (total_delivered>0)?(center_delivered*100)/total_delivered:0,
      (total_delivered>0)?((center_delivered*1000)/total_delivered)%10:0);
    $display("A3_STARVATION_STRESS_DONE");
    $finish;
  end
endmodule
