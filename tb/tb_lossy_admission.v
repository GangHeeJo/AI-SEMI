// [틀깨기 실험 A] 손실허용형 전송(Lossy Admission) — 지금까지는 "언젠가는 다 보낸다"
// 는 전제(공정 큐잉, QDEPTH=200000급 사실상 무한)로만 평가해왔음. 하지만 실제
// 하드웨어 큐는 작고 유한하고(예: 소스당 16~32개), 지속적 과부하(ρ>1, 실제 바쁜
// 장면에서는 흔한 상황)에서는 "언젠가 다 보낸다"가 물리적으로 불가능함 — 이 상황을
// "버그"로 피하는 대신 정면으로 받아들여서, 지표를 지연시간이 아니라
// **정보 보존율(delivered/generated, 즉 손실률의 반대)**로 바꿔서 잰다.
// 진짜 망막이 광수용체→신경절세포에서 100:1로 정보를 "버리는" 것과 같은 원리 —
// fovea의 중심 우선권이 "누가 먼저 받나"뿐 아니라 "누구 큐가 덜 넘쳐서 덜 버려지나"
// 로도 이어지는지 확인. 새 RTL 필요 없음 — 기존 true_traditional/fovea 그대로,
// 유한 QDEPTH+지속 과부하로 측정 방식만 바꿈.
`timescale 1ns/1ps
module tb_lossy_admission;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 16;        // 실제 하드웨어 버퍼 크기(소스당) — 유한, 넘치면 버림
  parameter ARRIVAL_PCT = 15;   // 우리 고전 "불안정 부하"(채널용량의 2~3배) 그대로 재사용

  reg clk = 0;
  reg rst;
  reg [15:0] req_plain, req_fovea, req_cluster;

  wire valid_plain; wire [3:0] addr_plain;
  wire valid_fovea; wire [3:0] addr_fovea;
  wire valid_cluster; wire [1:0] row_cluster; wire [3:0] col_mask_cluster;

  aer_tx16_trad_rowcol       tx_plain(.clk(clk), .rst(rst), .req(req_plain), .valid(valid_plain), .addr(addr_plain));
  `ifndef WEIGHT_VAL
  `define WEIGHT_VAL 5
  `endif
  aer_tx16_trad_rowcol_fovea #(.WEIGHT(`WEIGHT_VAL)) tx_fovea(.clk(clk), .rst(rst), .req(req_fovea), .valid(valid_fovea), .addr(addr_fovea));
  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(`WEIGHT_VAL)) tx_cluster(.clk(clk), .rst(rst), .req(req_cluster), .valid(valid_cluster), .row(row_cluster), .col_mask(col_mask_cluster));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_plain();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_fovea();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_cluster();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, draw, lat, c;
  integer gen_center, gen_periph; // 생성된(도착 시도한) 이벤트 수, 그룹별
  integer drop_center_plain, drop_periph_plain;
  integer drop_center_fovea, drop_periph_fovea;
  integer drop_center_cluster, drop_periph_cluster;

  function is_center(input integer idx_);
    is_center = (idx_==5 || idx_==6 || idx_==9 || idx_==10);
  endfunction

  initial begin
    rst = 1; req_plain = 16'd0; req_fovea = 16'd0; req_cluster = 16'd0;
    gen_center = 0; gen_periph = 0;
    drop_center_plain=0; drop_periph_plain=0; drop_center_fovea=0; drop_periph_fovea=0;
    drop_center_cluster=0; drop_periph_cluster=0;
    score_plain.init; score_fovea.init; score_cluster.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          if (is_center(i)) gen_center = gen_center + 1; else gen_periph = gen_periph + 1;
          // 큐가 이미 꽉 찼으면 이 도착은 버려짐(event_scoreboard.record_arrival과 동일 조건) — 그룹별로 직접 집계.
          if (score_plain.qcount[i] >= QDEPTH) begin
            if (is_center(i)) drop_center_plain = drop_center_plain + 1; else drop_periph_plain = drop_periph_plain + 1;
          end
          if (score_fovea.qcount[i] >= QDEPTH) begin
            if (is_center(i)) drop_center_fovea = drop_center_fovea + 1; else drop_periph_fovea = drop_periph_fovea + 1;
          end
          if (score_cluster.qcount[i] >= QDEPTH) begin
            if (is_center(i)) drop_center_cluster = drop_center_cluster + 1; else drop_periph_cluster = drop_periph_cluster + 1;
          end
          score_plain.record_arrival(i, cyc);
          score_fovea.record_arrival(i, cyc);
          score_cluster.record_arrival(i, cyc);
        end
      end
      for (i = 0; i < N; i = i + 1) begin
        req_plain[i] = (score_plain.qcount[i] > 0);
        req_fovea[i] = (score_fovea.qcount[i] > 0);
        req_cluster[i] = (score_cluster.qcount[i] > 0);
      end

      @(posedge clk); #1;

      if (valid_plain) lat = score_plain.record_departure(addr_plain, cyc);
      if (valid_fovea) lat = score_fovea.record_departure(addr_fovea, cyc);
      // cluster: 이긴 행의 col_mask 안에서 대기 중이던 열을 전부(최대 4개) 한 사이클에 배출.
      if (valid_cluster) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (col_mask_cluster[c]) lat = score_cluster.record_departure(row_cluster*4 + c, cyc);
        end
      end
    end

    $display("총 생성: center=%0d periph=%0d (도착 시도 기준)", gen_center, gen_periph);
    $display("[plain true_traditional] center 손실률=%0d.%0d%%  periph 손실률=%0d.%0d%%  전체=%0d.%0d%%",
      (drop_center_plain*100)/gen_center, ((drop_center_plain*1000)/gen_center)%10,
      (drop_periph_plain*100)/gen_periph, ((drop_periph_plain*1000)/gen_periph)%10,
      ((drop_center_plain+drop_periph_plain)*100)/(gen_center+gen_periph), (((drop_center_plain+drop_periph_plain)*1000)/(gen_center+gen_periph))%10);
    $display("[fovea]                   center 손실률=%0d.%0d%%  periph 손실률=%0d.%0d%%  전체=%0d.%0d%%",
      (drop_center_fovea*100)/gen_center, ((drop_center_fovea*1000)/gen_center)%10,
      (drop_periph_fovea*100)/gen_periph, ((drop_periph_fovea*1000)/gen_periph)%10,
      ((drop_center_fovea+drop_periph_fovea)*100)/(gen_center+gen_periph), (((drop_center_fovea+drop_periph_fovea)*1000)/(gen_center+gen_periph))%10);
    $display("[fovea+cluster]           center 손실률=%0d.%0d%%  periph 손실률=%0d.%0d%%  전체=%0d.%0d%%",
      (drop_center_cluster*100)/gen_center, ((drop_center_cluster*1000)/gen_center)%10,
      (drop_periph_cluster*100)/gen_periph, ((drop_periph_cluster*1000)/gen_periph)%10,
      ((drop_center_cluster+drop_periph_cluster)*100)/(gen_center+gen_periph), (((drop_center_cluster+drop_periph_cluster)*1000)/(gen_center+gen_periph))%10);
    $finish;
  end
endmodule
