// coincidence filter 검증: (1) 정확성(보존식: filtered+rejected=arrival, 블록당
// popcount>=2일 때만 통과하는지), (2) 고립 노이즈 vs 상관된 트래픽에서 실제로 다르게
// 동작하는지(핵심 주장 검증).
`timescale 1ns/1ps
module tb_coincidence_filter;
  reg [15:0] arrival;
  wire [15:0] filtered, rejected;

  aer_coincidence_filter dut(.arrival(arrival), .filtered_arrival(filtered), .noise_rejected(rejected));

  integer rng_seed;
  integer trial, i, draw, errors;
  integer noise_total, noise_passed, noise_rejected_cnt;
  integer burst_total, burst_passed, burst_rejected_cnt;

  task automatic check_conservation;
    begin
      if ((filtered | rejected) !== arrival) begin
        errors = errors + 1;
        $display("CONSERVATION_FAIL arrival=%b filtered=%b rejected=%b", arrival, filtered, rejected);
      end
      if ((filtered & rejected) !== 16'd0) begin
        errors = errors + 1;
        $display("OVERLAP_FAIL arrival=%b filtered=%b rejected=%b", arrival, filtered, rejected);
      end
    end
  endtask

  initial begin
    errors = 0;
    rng_seed = 11;
    noise_total = 0; noise_passed = 0; noise_rejected_cnt = 0;
    burst_total = 0; burst_passed = 0; burst_rejected_cnt = 0;

    // 시나리오 A: 순수 고립 노이즈(항상 정확히 소스 1개만 무작위로 발화 -- 절대 같은
    // 블록에 2개가 같이 뜰 일이 없음, popcount는 항상 정확히 1) -- 전부 rejected여야 함.
    for (trial = 0; trial < 2000; trial = trial + 1) begin
      arrival = 16'd0;
      draw = ($random(rng_seed) % 16 + 16) % 16;
      arrival[draw] = 1'b1;
      #1;
      check_conservation;
      if (filtered != 16'd0) begin
        noise_passed = noise_passed + popcount_disp(filtered);
      end
      noise_rejected_cnt = noise_rejected_cnt + popcount_disp(rejected);
      noise_total = noise_total + 1;
    end

    // 시나리오 B: 블록 상관 버스트 -- 매번 한 블록을 골라 그 블록의 4개 소스 중
    // 3개를 동시에 발화(진짜 물체 가장자리처럼) -- 전부 filtered로 통과해야 함.
    for (trial = 0; trial < 2000; trial = trial + 1) begin
      arrival = 16'd0;
      case (($random(rng_seed) % 4 + 4) % 4)
        0: begin arrival[0]=1; arrival[1]=1; arrival[4]=1; end // TL 3개
        1: begin arrival[2]=1; arrival[3]=1; arrival[6]=1; end // TR 3개
        2: begin arrival[8]=1; arrival[9]=1; arrival[12]=1; end // BL 3개
        3: begin arrival[10]=1; arrival[11]=1; arrival[14]=1; end // BR 3개
      endcase
      #1;
      check_conservation;
      burst_passed = burst_passed + popcount_disp(filtered);
      burst_rejected_cnt = burst_rejected_cnt + popcount_disp(rejected);
      burst_total = burst_total + 1;
    end

    $display("[isolated noise] trials=%0d events=%0d passed=%0d rejected=%0d (rejection_rate=%0d%%)",
      noise_total, noise_total, noise_passed, noise_rejected_cnt, (noise_rejected_cnt*100)/noise_total);
    $display("[correlated burst] trials=%0d events=%0d passed=%0d rejected=%0d (pass_rate=%0d%%)",
      burst_total, burst_total*3, burst_passed, burst_rejected_cnt, (burst_passed*100)/(burst_total*3));

    if (errors == 0 && noise_passed == 0 && burst_rejected_cnt == 0)
      $display("COINCIDENCE_FILTER_PASS");
    else
      $display("COINCIDENCE_FILTER_FAIL errors=%0d noise_passed=%0d burst_rejected=%0d", errors, noise_passed, burst_rejected_cnt);
    $finish;
  end

  function integer popcount_disp;
    input [15:0] v;
    integer j;
    begin
      popcount_disp = 0;
      for (j = 0; j < 16; j = j + 1) popcount_disp = popcount_disp + v[j];
    end
  endfunction
endmodule
