// activity 카운터가 감쇠 전에 16비트를 넘어 오버플로우(랩어라운드)하는지 직접 확인.
// new_event를 매 사이클 강제로 꽉 채워서(4/cycle) 최악의 증가 속도를 만든다.
`ifndef DECAY_SHIFT_VAL
`define DECAY_SHIFT_VAL 14
`endif
module tb_activity_overflow;
  reg clk = 0;
  reg rst;
  reg [15:0] req;
  reg [15:0] new_event;
  wire valid, addr_type;
  wire [1:0] addr;

  aer_tx16_adaptive_v2 #(.DECAY_SHIFT(`DECAY_SHIFT_VAL)) tx(.clk(clk), .rst(rst), .req(req), .new_event(new_event), .valid(valid), .addr_type(addr_type), .addr(addr));

  always #5 clk = ~clk;

  integer cyc;
  integer max_seen [0:3];
  integer i;

  initial begin
    rst = 1; req = 16'hFFFF; new_event = 16'hFFFF;
    for (i=0;i<4;i=i+1) max_seen[i] = 0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < (1 << `DECAY_SHIFT_VAL) + 2000; cyc = cyc + 1) begin
      @(posedge clk); #1;
      for (i = 0; i < 4; i = i + 1)
        if (tx.activity[i] > max_seen[i]) max_seen[i] = tx.activity[i];
      // 랩어라운드(오버플로우) 감지: activity가 이전보다 갑자기 크게 떨어지면서 decay_tick도 아닌 경우
      if (cyc > 0 && tx.activity[0] < 100 && max_seen[0] > 60000)
        $display("WRAPAROUND 감지 의심: cyc=%0d activity[0]=%0d (직전 최댓값=%0d)", cyc, tx.activity[0], max_seen[0]);
    end
    $display("DECAY_SHIFT=%0d, 관측된 activity 최댓값=[%0d,%0d,%0d,%0d] (16비트 한계=65535)", `DECAY_SHIFT_VAL, max_seen[0],max_seen[1],max_seen[2],max_seen[3]);
    $finish;
  end
endmodule
