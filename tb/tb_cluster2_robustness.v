// cluster2 로버스트니스 -- round 없어져서 "팀 간 경쟁"은 사라졌지만, 팀 내부(row1 vs
// row2, row0 vs row3)는 여전히 arbiter2로 공정해야 하고, 완전포화 시 영구 기아(§37)가
// 없어야 함(col_arb 자체가 없으므로 구조적으로 면역이어야 정상).
`timescale 1ns/1ps
module tb_cluster2_robustness;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2 dut(
    .clk(clk), .rst(rst), .req(req),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer visits [0:15];
  integer max_gap [0:15];
  integer last_grant [0:15];
  integer cyc, i, c, idx;
  integer fail;

  task automatic observe_lane(input integer valid_in, input integer row_in, input [3:0] mask_in);
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (last_grant[idx] >= 0 && (cyc - last_grant[idx]) > max_gap[idx])
              max_gap[idx] = cyc - last_grant[idx];
            last_grant[idx] = cyc;
            visits[idx] = visits[idx] + 1;
          end
        end
      end
    end
  endtask

  initial begin
    fail = 0;
    for (i = 0; i < 16; i = i + 1) begin visits[i] = 0; max_gap[i] = 0; last_grant[i] = -1; end
    rst = 1; req = 16'd0;
    @(posedge clk); #1;
    rst = 0;

    // 완전포화 20000cycle.
    req = 16'hFFFF;
    for (cyc = 0; cyc < 20000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      observe_lane(valid0, row0, col_mask0);
      observe_lane(valid1, row1, col_mask1);
    end

    for (i = 0; i < 16; i = i + 1) begin
      $display("source=%0d visits=%0d max_gap=%0d", i, visits[i], max_gap[i]);
      if (visits[i] == 0) begin
        $display("FAIL: source=%0d 완전포화 20000cycle 내내 영구 기아", i);
        fail = fail + 1;
      end else if (max_gap[i] > 40) begin
        $display("FAIL: source=%0d gap=%0d 과도함", i, max_gap[i]);
        fail = fail + 1;
      end
    end

    if (fail == 0) $display("=== CLUSTER2 로버스트니스 전부 통과 ===");
    else $display("=== CLUSTER2 로버스트니스 실패 %0d건 ===", fail);
    $finish;
  end
endmodule
