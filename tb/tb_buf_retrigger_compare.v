// "같은 소스 연속 재발화"(limit_retrigger류) 시나리오에서 cluster(버퍼 없음) vs
// cluster_buf(2-deep 버퍼) 직접 비교. 공용 스코어보드(aer_clean_tb.sv)와 똑같이
// "요청 생성"과 "grant 시 pending 해제"를 별도의 always @(posedge clk) 블록으로
// 나눠서, 넌블로킹(<=) 대입 때문에 생기는 진짜 1사이클 공백(같은 엣지에 새 요청과
// 이전 grant의 해제가 동시에 걸리면, 해제가 아직 안 보이는 그 레이스)을 그대로
// 재현한다 -- 이래야 예전에 실측한 128/256(§본문) 결과가 재현되는지 확인 가능함.
`timescale 1ns/1ps
module tb_buf_retrigger_compare;
  parameter CYCLES = 256;

  reg clk = 0;
  reg rst;

  // --- cluster(버퍼 없음, 레벨 req) ---
  reg [15:0] req_plain;
  wire valid_plain; wire [1:0] row_plain; wire [3:0] colmask_plain;
  aer_tx16_trad_rowcol_fovea_cluster #(.WEIGHT(5)) tx_plain(
    .clk(clk), .rst(rst), .req(req_plain), .valid(valid_plain), .row(row_plain), .col_mask(colmask_plain));
  reg pending0_plain;
  integer overrun_plain, generated_plain, delivered_plain;
  integer cyc_plain;

  // --- cluster_buf(2-deep 버퍼, 펄스 arrival) ---
  reg [15:0] arrival_buf;
  wire [15:0] overrun_buf_w;
  wire valid_buf; wire [1:0] row_buf; wire [3:0] colmask_buf;
  aer_tx16_trad_rowcol_fovea_cluster_buf #(.WEIGHT(5)) tx_buf(
    .clk(clk), .rst(rst), .arrival(arrival_buf), .overrun(overrun_buf_w),
    .valid(valid_buf), .row(row_buf), .col_mask(colmask_buf));
  integer overrun_buf, generated_buf, delivered_buf;

  always #5 clk = ~clk;

  // ---- plain cluster: 두 블록으로 분리(공용 스코어보드와 동일한 레이스 재현) ----
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      generated_plain <= 0; overrun_plain <= 0; cyc_plain <= 0;
    end else if (cyc_plain < CYCLES) begin
      // "요청 생성" -- 이 사이클 시작 시점의 pending0_plain(아직 이번 엣지의 해제가
      // 반영 안 된 값)을 보고 판단.
      generated_plain <= generated_plain + 1;
      if (pending0_plain) overrun_plain <= overrun_plain + 1;
      cyc_plain <= cyc_plain + 1;
    end
  end
  always @(*) begin
    req_plain = 16'd0;
    req_plain[0] = pending0_plain;
  end
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      pending0_plain <= 1'b0; delivered_plain <= 0;
    end else begin
      // grant되면 해제(넌블로킹, 이번 사이클 "요청 생성" 블록은 못 봄).
      if (valid_plain && (row_plain == 2'd0) && colmask_plain[0]) begin
        pending0_plain <= 1'b0;
        delivered_plain <= delivered_plain + 1;
      end else if (cyc_plain < CYCLES) begin
        pending0_plain <= 1'b1; // 매 사이클 재요청 시도(아직 pending이면 유지)
      end
    end
  end

  // ---- buf cluster: 매 사이클 그냥 arrival 펄스, 회로 자체가 overrun 판단(비교용 단순 모델) ----
  integer cyc_buf;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      generated_buf <= 0; overrun_buf <= 0; delivered_buf <= 0; cyc_buf <= 0; arrival_buf <= 16'd0;
    end else begin
      if (cyc_buf < CYCLES) begin
        generated_buf <= generated_buf + 1;
        arrival_buf <= 16'd1;
        cyc_buf <= cyc_buf + 1;
      end else begin
        arrival_buf <= 16'd0;
      end
      if (overrun_buf_w[0]) overrun_buf <= overrun_buf + 1;
      if (valid_buf && (row_buf == 2'd0) && colmask_buf[0]) delivered_buf <= delivered_buf + 1;
    end
  end

  initial begin
    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
    wait (cyc_plain >= CYCLES && cyc_buf >= CYCLES);
    repeat (10) @(posedge clk);
    $display("[cluster(버퍼없음)] generated=%0d overrun=%0d delivered=%0d", generated_plain, overrun_plain, delivered_plain);
    $display("[cluster_buf(2-deep)] generated=%0d overrun=%0d delivered=%0d", generated_buf, overrun_buf, delivered_buf);
    $finish;
  end
endmodule
