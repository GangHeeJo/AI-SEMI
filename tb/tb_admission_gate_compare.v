// homeostatic admission gate 검증 -- "손실률은 안 줄어들지만(큐잉이론 예측) 지연시간
// 예측가능성은 개선된다"는 주장을 직접 검증한다. fovea+cluster 단독 vs
// fovea+cluster+admission_gate를 같은 도착 스트림(같은 RNG draw)으로 나란히 비교.
`timescale 1ns/1ps
module tb_admission_gate_compare;
  parameter N = 16;
  parameter CYCLES = 20000;
  parameter QDEPTH = 16;
  parameter ARRIVAL_PCT = 15;
  parameter WEIGHT_VAL = 5;

  reg clk = 0;
  reg rst;
  reg [15:0] req_plain, req_gated;
  reg [15:0] arrival_pulse, pending_in;

  wire valid_plain; wire [1:0] row_plain; wire [3:0] colmask_plain;
  wire valid_gated; wire [1:0] row_gated; wire [3:0] colmask_gated;
  wire [15:0] admit; wire pressure;

  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(WEIGHT_VAL)) tx_plain(
    .clk(clk), .rst(rst), .req(req_plain), .valid(valid_plain), .row(row_plain), .col_mask(colmask_plain));
  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(WEIGHT_VAL)) tx_gated(
    .clk(clk), .rst(rst), .req(req_gated), .valid(valid_gated), .row(row_gated), .col_mask(colmask_gated));

  aer_admission_gate #(.UTIL_BITS(8), .UTIL_HIGH(252), .UTIL_LOW(240)) gate(
    .clk(clk), .rst(rst), .tx_valid(valid_gated), .arrival(arrival_pulse), .pending(pending_in),
    .admit(admit), .pressure(pressure));

  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_plain();
  event_scoreboard #(.N(N), .QDEPTH(QDEPTH)) score_gated();

  always #5 clk = ~clk;

  integer rng_seed = 1;
  integer cyc, i, c, draw, lat, idx;
  integer generated;
  integer drop_overflow_plain;
  integer drop_overflow_gated, drop_gate_reject;
  integer pressure_cycles;
  integer sum_lat_plain, cnt_lat_plain, max_lat_plain;
  integer sum_lat_gated, cnt_lat_gated, max_lat_gated;

  initial begin
    rst = 1; req_plain = 16'd0; req_gated = 16'd0; arrival_pulse = 16'd0; pending_in = 16'd0;
    generated = 0;
    drop_overflow_plain = 0; drop_overflow_gated = 0; drop_gate_reject = 0;
    pressure_cycles = 0;
    sum_lat_plain = 0; cnt_lat_plain = 0; max_lat_plain = 0;
    sum_lat_gated = 0; cnt_lat_gated = 0; max_lat_gated = 0;
    score_plain.init; score_gated.init;
    @(posedge clk); #1;
    rst = 0;

    for (cyc = 0; cyc < CYCLES; cyc = cyc + 1) begin
      arrival_pulse = 16'd0;
      for (i = 0; i < N; i = i + 1)
        pending_in[i] = (score_gated.qcount[i] > 0);

      for (i = 0; i < N; i = i + 1) begin
        draw = (($random(rng_seed) % 100 + 100) % 100);
        if (draw < ARRIVAL_PCT) begin
          generated = generated + 1;
          arrival_pulse[i] = 1'b1;
          // plain(게이트 없음): 기존 lossy-admission과 동일하게 큐 꽉 찼으면 드롭.
          if (score_plain.qcount[i] >= QDEPTH)
            drop_overflow_plain = drop_overflow_plain + 1;
          score_plain.record_arrival(i, cyc);
        end
      end

      // admission gate는 조합논리 출력(이번 사이클 arrival_pulse/pending_in 기준)이라
      // 바로 admit을 읽어서 gated 큐에 반영한다.
      #1;
      for (i = 0; i < N; i = i + 1) begin
        if (arrival_pulse[i]) begin
          if (admit[i]) begin
            if (score_gated.qcount[i] >= QDEPTH)
              drop_overflow_gated = drop_overflow_gated + 1;
            score_gated.record_arrival(i, cyc);
          end else begin
            drop_gate_reject = drop_gate_reject + 1;
          end
        end
      end
      if (pressure) pressure_cycles = pressure_cycles + 1;

      for (i = 0; i < N; i = i + 1) begin
        req_plain[i] = (score_plain.qcount[i] > 0);
        req_gated[i] = (score_gated.qcount[i] > 0);
      end

      @(posedge clk); #1;

      if (valid_plain) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (colmask_plain[c]) begin
            idx = row_plain*4 + c;
            lat = score_plain.record_departure(idx, cyc);
            if (lat >= 0) begin
              sum_lat_plain = sum_lat_plain + lat; cnt_lat_plain = cnt_lat_plain + 1;
              if (lat > max_lat_plain) max_lat_plain = lat;
            end
          end
        end
      end
      if (valid_gated) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (colmask_gated[c]) begin
            idx = row_gated*4 + c;
            lat = score_gated.record_departure(idx, cyc);
            if (lat >= 0) begin
              sum_lat_gated = sum_lat_gated + lat; cnt_lat_gated = cnt_lat_gated + 1;
              if (lat > max_lat_gated) max_lat_gated = lat;
            end
          end
        end
      end
    end

    $display("총 생성(도착 시도): %0d", generated);
    $display("[cluster only]       overflow_drop=%0d(%0d.%0d%%)  avg_lat=%0d  max_lat=%0d",
      drop_overflow_plain, (drop_overflow_plain*100)/generated, ((drop_overflow_plain*1000)/generated)%10,
      cnt_lat_plain>0 ? sum_lat_plain/cnt_lat_plain : 0, max_lat_plain);
    $display("[cluster+gate]       overflow_drop=%0d  gate_reject=%0d  총거부=%0d(%0d.%0d%%)  avg_lat=%0d  max_lat=%0d  pressure_cycles=%0d(%0d%%)",
      drop_overflow_gated, drop_gate_reject, drop_overflow_gated+drop_gate_reject,
      ((drop_overflow_gated+drop_gate_reject)*100)/generated, (((drop_overflow_gated+drop_gate_reject)*1000)/generated)%10,
      cnt_lat_gated>0 ? sum_lat_gated/cnt_lat_gated : 0, max_lat_gated,
      pressure_cycles, (pressure_cycles*100)/CYCLES);
    $finish;
  end
endmodule
