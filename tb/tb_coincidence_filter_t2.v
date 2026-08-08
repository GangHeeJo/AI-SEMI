// T=2 coincidence filter 검증: (1) 순수 고립 노이즈 억제, (2) 같은 사이클 상관 통과
// (T=1과 동일 동작 유지), (3) **직전+다음 사이클에 걸친 상관도 통과**(T=1은 못 잡던
// 케이스 -- 이게 이번 확장의 핵심).
`timescale 1ns/1ps
module tb_coincidence_filter_t2;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] filtered, rejected;

  aer_coincidence_filter_t2 dut(.clk(clk), .rst(rst), .arrival(arrival),
    .filtered_arrival(filtered), .noise_rejected(rejected));

  always #5 clk = ~clk;

  integer rng_seed = 13;
  integer trial, draw, errors;
  integer noise_passed, noise_rejected_cnt;
  integer same_cyc_passed, same_cyc_rejected;
  integer cross_cyc_passed, cross_cyc_rejected;

  task automatic check_conservation;
    begin
      if ((filtered & rejected) !== 16'd0) begin
        errors = errors + 1;
        $display("OVERLAP_FAIL filtered=%b rejected=%b", filtered, rejected);
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; errors = 0;
    noise_passed = 0; noise_rejected_cnt = 0;
    same_cyc_passed = 0; same_cyc_rejected = 0;
    cross_cyc_passed = 0; cross_cyc_rejected = 0;
    @(posedge clk); #1;
    rst = 0;

    // 시나리오 A: 순수 고립 노이즈 -- 소스 1개만 발화, 그 다음 사이클엔 아무도 없음.
    // (한 arrival의 판정 결과는 그걸 넣은 엣지로부터 2엣지 뒤에 나옴 -- prev_arrival로
    // 캡처되는 데 1엣지, 그 prev_arrival을 판정한 filtered/rejected가 등록되는 데 1엣지.)
    for (trial = 0; trial < 1000; trial = trial + 1) begin
      arrival = 16'd0;
      draw = ($random(rng_seed) % 16 + 16) % 16;
      arrival[draw] = 1'b1;
      @(posedge clk); #1;      // 엣지1: prev_arrival<=draw 캡처됨
      check_conservation;
      arrival = 16'd0;         // 다음 사이클엔 확실히 비움(진짜 고립임을 보장)
      @(posedge clk); #1;      // 엣지2: filtered/rejected<=f(draw) 등록됨, 지금 보임
      check_conservation;
      noise_passed = noise_passed + popcount_disp(filtered);
      noise_rejected_cnt = noise_rejected_cnt + popcount_disp(rejected);
    end

    // 시나리오 B: 같은 사이클 상관(T=1 케이스, 여전히 잡혀야 함) -- TL 블록 2개 동시.
    // (이중판정 수정 후로는 확인이 즉시(같은 엣지)일어나므로 두 엣지 다 합산해서 확인.)
    for (trial = 0; trial < 1000; trial = trial + 1) begin
      arrival = 16'd0; arrival[0] = 1; arrival[1] = 1;
      @(posedge clk); #1;
      check_conservation;
      same_cyc_passed = same_cyc_passed + popcount_disp(filtered);
      same_cyc_rejected = same_cyc_rejected + popcount_disp(rejected);
      arrival = 16'd0;
      @(posedge clk); #1;
      check_conservation;
      same_cyc_passed = same_cyc_passed + popcount_disp(filtered);
      same_cyc_rejected = same_cyc_rejected + popcount_disp(rejected);
    end

    // 시나리오 C: 걸친 상관(T=1은 못 잡음, T=2가 새로 잡아야 함) -- TL의 소스0이 먼저,
    // 그 다음 사이클에 같은 블록의 소스1이 옴. 소스0의 판정은 소스1이 들어온 뒤
    // 1엣지 더 지나야 나옴(window=prev_arrival|arrival이 소스1 들어온 사이클에 완성되고,
    // 그 다음 엣지에 등록).
    for (trial = 0; trial < 1000; trial = trial + 1) begin
      arrival = 16'd0; arrival[0] = 1;
      @(posedge clk); #1;      // 엣지1: prev_arrival<=src0 캡처
      check_conservation;
      arrival = 16'd0; arrival[1] = 1;
      @(posedge clk); #1;      // 엣지2: filtered<=f(src0, window=src0|src1) 등록(src0 판정 완료), prev_arrival<=src1
      check_conservation;
      cross_cyc_passed = cross_cyc_passed + popcount_disp(filtered);
      cross_cyc_rejected = cross_cyc_rejected + popcount_disp(rejected);
      arrival = 16'd0;
      @(posedge clk); #1;      // 엣지3: filtered<=f(src1, window=src1|0) 등록(src1 판정 완료)
      check_conservation;
      cross_cyc_passed = cross_cyc_passed + popcount_disp(filtered);
      cross_cyc_rejected = cross_cyc_rejected + popcount_disp(rejected);
    end

    $display("[isolated noise 1cyc-apart] passed=%0d rejected=%0d (rejection_rate=%0d%%)",
      noise_passed, noise_rejected_cnt, (noise_rejected_cnt*100)/(noise_passed+noise_rejected_cnt));
    $display("[same-cycle coincidence]    passed=%0d rejected=%0d", same_cyc_passed, same_cyc_rejected);
    $display("[cross-cycle coincidence]   passed=%0d rejected=%0d (T=1이면 여기가 0/2000일 것)",
      cross_cyc_passed, cross_cyc_rejected);

    if (errors == 0 && noise_passed == 0 && same_cyc_rejected == 0 && cross_cyc_rejected == 0)
      $display("COINCIDENCE_FILTER_T2_PASS");
    else
      $display("COINCIDENCE_FILTER_T2_FAIL errors=%0d", errors);
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
