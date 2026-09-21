// Digital 2차 top-level 통합(v2) -- v1(1단계, theta_idx를 외부 입력으로 받음)에
// rtl/bayes_filter_v1.v(2단계 predictor의 §133 스냅샷, 256단계/64x64 -- §134/135에서
// bayes_filter.v 본체를 1024단계/1024x1024 신규 타겟으로 키우면서 이 파일이 깨지지 않도록
// v1과 짝이 맞는 옛 크기로 얼려둔 사본)를 붙여 theta_idx를 외부에서 안 받고 내부에서 만들어
// 쓰는 완전한 파이프라인으로 만든다.
//
// predictor는 이벤트 하나(row,col,pol)를 받아 처리하는 데 대략 512~768사이클이 걸리는
// 직렬 필터(rtl/bayes_filter.v 헤더 참고)라, 1단계처럼 사이클당 최대 16개 이벤트를 받는
// arrival 버스를 그대로 못 따라감 -- 이 파일의 프론트엔드가 그 속도차를 흡수한다.
//
// 프론트엔드: 16개 소스마다 1비트 pending 래치(+ 도착 시점 극성 래치)를 두고, 매 사이클
// pending 중 가장 낮은 인덱스 하나를 predictor가 한가할 때(!busy)만 밀어 넣는다. 이미
// pending인 소스에 새 이벤트가 또 도착하면 pred_overrun으로 집계만 하고 버림(정직한 처리량
// 한계 -- world_mem_writer의 overrun과 같은 성격). predictor가 하나뿐이라 여러 소스 사이의
// 완전한 공정성(라운드로빈)보다 단순함을 택함(ponytail: 필요해지면 arbiter16로 교체).
module aer_tx16_coord_transform_v2 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  output [15:0] overrun,       // 1단계(TX) overrun -- v1과 동일
  output [7:0]  wmem_overrun,  // 1단계(world_mem_writer) overrun -- v1과 동일
  output [15:0] pred_overrun,  // predictor 프론트엔드가 못 따라가서 버린 이벤트(소스별)
  output [7:0]  theta_idx_out, // predictor가 지금까지 추정한 전역 회전각(관찰용)

  output              world_we,
  output [11:0]       world_addr,
  output              world_pol
);
  reg [15:0] pending, pending_pol;
  assign pred_overrun = arrival & pending;

  wire        bf_busy, bf_valid_out;
  wire [7:0]  bf_theta_out;

  reg  [3:0] win_idx;
  reg        win_found;
  integer    i;
  always @(*) begin
    win_found = 1'b0;
    win_idx = 4'd0;
    for (i = 15; i >= 0; i = i - 1)
      if (pending[i]) begin win_found = 1'b1; win_idx = i[3:0]; end
  end
  wire win_valid = win_found && !bf_busy;

  integer k;
  always @(posedge clk) begin
    if (rst) begin
      pending <= 16'd0;
      pending_pol <= 16'd0;
    end else begin
      for (k = 0; k < 16; k = k + 1) begin
        if (win_valid && win_idx == k[3:0])
          pending[k] <= 1'b0;
        else if (arrival[k] && !pending[k]) begin
          pending[k] <= 1'b1;
          pending_pol[k] <= polarity_in[k];
        end
      end
    end
  end

  bayes_filter_v1 u_bf (
    .clk(clk), .rst(rst),
    .valid_in(win_valid),
    .row_in(win_idx[3:2]), .col_in(win_idx[1:0]), .pol_in(pending_pol[win_idx]),
    .busy(bf_busy), .valid_out(bf_valid_out), .theta_out(bf_theta_out)
  );

  reg [7:0] theta_idx_reg;
  always @(posedge clk) begin
    if (rst) theta_idx_reg <= 8'd0;
    else if (bf_valid_out) theta_idx_reg <= bf_theta_out;
  end
  assign theta_idx_out = theta_idx_reg;

  aer_tx16_coord_transform_v1 u_v1 (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx(theta_idx_reg),
    .overrun(overrun), .wmem_overrun(wmem_overrun),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );
endmodule
