// arbiter4_tree 정확성(one-hot/요청자만 grant) + 로버스트니스(전원 포화 시 각 입력의
// 최대 grant 간격, 즉 기아 여부)를 arbiter4(회전식)와 나란히 검증.
`timescale 1ns/1ps
module tb_arbiter4_tree;
  reg clk = 0;
  reg rst;
  reg [3:0] req;
  wire [3:0] gnt_tree, gnt_rr;
  integer errors = 0;
  integer i;

  arbiter4_tree tree_dut(.clk(clk), .rst(rst), .req(req), .gnt(gnt_tree));
  arbiter4      rr_dut  (.clk(clk), .rst(rst), .req(req), .gnt(gnt_rr));

  always #5 clk = ~clk;

  task check_onehot_or_zero;
    input [3:0] g;
    input [3:0] r;
    begin
      if ((g & (g - 1)) !== 0) begin
        $display("FAIL: gnt=%b is not one-hot/zero", g); errors = errors + 1;
      end
      if ((g & ~r) !== 0) begin
        $display("FAIL: gnt=%b granted a non-requester (req=%b)", g, r); errors = errors + 1;
      end
    end
  endtask

  integer last_tree [0:3];
  integer last_rr [0:3];
  integer max_gap_tree [0:3];
  integer max_gap_rr [0:3];
  integer cyc;

  initial begin
    rst = 1; req = 4'b0000;
    for (i = 0; i < 4; i = i + 1) begin last_tree[i]=-1; last_rr[i]=-1; max_gap_tree[i]=0; max_gap_rr[i]=0; end
    @(posedge clk); #1;
    rst = 0;

    // (1) 결정론적 케이스: 단일/부분 요청에서 one-hot·요청자만 grant 확인
    req = 4'b0100; @(posedge clk); #1; check_onehot_or_zero(gnt_tree, req); check_onehot_or_zero(gnt_rr, req);
    req = 4'b1010; @(posedge clk); #1; check_onehot_or_zero(gnt_tree, req); check_onehot_or_zero(gnt_rr, req);
    req = 4'b1111; @(posedge clk); #1; check_onehot_or_zero(gnt_tree, req); check_onehot_or_zero(gnt_rr, req);
    req = 4'b0000; @(posedge clk); #1; check_onehot_or_zero(gnt_tree, req); check_onehot_or_zero(gnt_rr, req);

    // (2) 전원 포화(4개 전부 100% 요청) 5000cycle 동안 각 입력의 최대 grant 간격(기아 여부)
    req = 4'b1111;
    for (cyc = 0; cyc < 5000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      for (i = 0; i < 4; i = i + 1) begin
        if (gnt_tree[i]) begin
          if (last_tree[i] >= 0 && (cyc - last_tree[i]) > max_gap_tree[i]) max_gap_tree[i] = cyc - last_tree[i];
          last_tree[i] = cyc;
        end
        if (gnt_rr[i]) begin
          if (last_rr[i] >= 0 && (cyc - last_rr[i]) > max_gap_rr[i]) max_gap_rr[i] = cyc - last_rr[i];
          last_rr[i] = cyc;
        end
      end
    end

    for (i = 0; i < 4; i = i + 1)
      $display("입력%0d: tree max_gap=%0d, round-robin max_gap=%0d", i, max_gap_tree[i], max_gap_rr[i]);

    for (i = 0; i < 4; i = i + 1) begin
      if (max_gap_tree[i] > 20) begin
        $display("FAIL: tree 입력%0d 기아 의심(gap=%0d)", i, max_gap_tree[i]); errors = errors + 1;
      end
    end

    if (errors == 0) $display("=== arbiter4_tree 검증 전부 통과 ===");
    else $display("=== 실패 %0d건 ===", errors);
    $finish;
  end
endmodule
