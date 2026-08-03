// hot_arb가 실제로 row0/row3를 공평하게 번갈아 뽑는지 직접 추적하는 디버그 벤치.
module tb_debug_hotarb;
  parameter CYCLES = 1500;
  parameter QDEPTH = 64;
  parameter BG_PCT = 3;
  parameter HOT_PCT = 50;

  reg clk = 0;
  reg rst;
  reg [15:0] req;
  wire       valid, addr_type;
  wire [1:0] addr;

  aer_tx16_adaptive tx(.clk(clk), .rst(rst), .req(req), .valid(valid), .addr_type(addr_type), .addr(addr));

  always #5 clk = ~clk;

  integer rng_seed = 1;
  event_scoreboard #(.N(16), .QDEPTH(QDEPTH)) score();
  integer cyc, i;

  integer row_pick_count [0:3]; // ROW 패킷으로 실제 선택된 행 카운트(누적)

  function is_hotspot(input integer idx_);
    is_hotspot = (idx_==0 || idx_==3 || idx_==12 || idx_==15);
  endfunction

  initial begin
    rst = 1; req = 16'd0;
    score.init;
    for (i=0;i<4;i=i+1) row_pick_count[i]=0;
    @(posedge clk); #1; rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < 16; i = i + 1) begin
        if ((($random(rng_seed) % 100 + 100) % 100) < (is_hotspot(i) ? HOT_PCT : BG_PCT)) begin
          score.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < 16; i = i + 1) req[i] = (score.qcount[i] > 0);

      @(posedge clk); #1;

      if (valid && addr_type==1'b0) begin
        row_pick_count[addr] = row_pick_count[addr] + 1;
        if (cyc > 700 && cyc < 900)
          $display("cyc=%0d ROW picked=%0d | hot_mask=%b use_hot=%b use_cold=%b | hot_arb.req=%b hot_arb.gnt=%b hot_arb.last_gnt=%0d | round=%0d",
            cyc, addr, tx.hot_mask, tx.use_hot, tx.use_cold,
            tx.hot_arb.req, tx.hot_arb.gnt, tx.hot_arb.last_gnt, tx.round);
      end else begin
        // 큐가 다 차서 넘치는 걸 대략 방지: row 방문 없이도 시뮬레이션 계속 진행
      end

      // 실제 이벤트 소비는 안 하고(수신기 없음), 그냥 요청만 계속 살아있게 둔다
      // -> 큐 오버플로우로 인한 왜곡을 피하려면 여기서 직접 안 비우고 req 레벨만 유지
    end

    $display("row_pick_count = [%0d,%0d,%0d,%0d]", row_pick_count[0], row_pick_count[1], row_pick_count[2], row_pick_count[3]);
    $finish;
  end
endmodule
