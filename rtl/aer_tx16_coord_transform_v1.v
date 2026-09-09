// Digital 2차 1단계 통합 top -- steal_buf_polarity(1차 TX, 최대 8 events/cycle) ->
// 로컬(row,col) 디코드 -> coord_transform_rmcm(8레인 병렬, 채택안) -> world_mem_writer.
//
// theta_idx는 "지금 이 순간의 세계 회전각"을 나타내는 외부 라이브 입력(1단계 정의: 회전각이
// 주어진다) -- steal_buf_polarity가 버퍼링 때문에 이벤트를 늦게 배출할 수 있는데, 이 설계는
// "배출되는 바로 그 사이클에 살아있는 theta"를 쓴다(원래 발화 사이클의 theta가 아님). 버퍼
// 깊이가 최대 2라 지연은 최대 몇 사이클뿐이지만, 이건 명시적으로 드러내는 1단계 단순화이고
// 회전이 매우 빠르면 오차 원인이 될 수 있음 -- 실측(통합 TB)으로 문제 되면 그때 페이로드에
// 타임스탬프를 추가하는 방향으로 넘어감(1차 AER 패킷은 고의로 안 건드림, progress.md 참고).
module aer_tx16_coord_transform_v1 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  input  [7:0]  theta_idx,
  output [15:0] overrun,

  input               rd_en,
  input  [5:0]        rd_x,
  input  [5:0]        rd_y,
  output              rd_written,
  output              rd_pol
);
  wire       valid0, valid1;
  wire [1:0] row0, row1;
  wire [3:0] col_mask0, col_mask1, pol_mask0, pol_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity u_tx (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .pol_mask0(pol_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .pol_mask1(pol_mask1)
  );

  // lane 0~3 = row0의 col 0~3, lane 4~7 = row1의 col 0~3
  wire [7:0]       ev_valid;
  wire signed [3:0] ev_xc2 [0:7];
  wire signed [3:0] ev_yc2 [0:7];
  wire             ev_pol  [0:7];

  genvar g;
  generate
    for (g = 0; g < 4; g = g + 1) begin : DECODE0
      assign ev_valid[g]  = valid0 & col_mask0[g];
      assign ev_xc2[g]    = 2*g - 3;
      assign ev_yc2[g]    = 2*row0 - 3;
      assign ev_pol[g]    = pol_mask0[g];
    end
    for (g = 0; g < 4; g = g + 1) begin : DECODE1
      assign ev_valid[4+g] = valid1 & col_mask1[g];
      assign ev_xc2[4+g]   = 2*g - 3;
      assign ev_yc2[4+g]   = 2*row1 - 3;
      assign ev_pol[4+g]   = pol_mask1[g];
    end
  endgenerate

  wire [7:0] xf_valid;
  wire [5:0] xf_x [0:7];
  wire [5:0] xf_y [0:7];
  reg        xf_pol_d1 [0:7];

  generate
    for (g = 0; g < 8; g = g + 1) begin : XFORM
      coord_transform_rmcm u_xf (
        .clk(clk), .rst(rst),
        .valid_in(ev_valid[g]), .xc2_in(ev_xc2[g]), .yc2_in(ev_yc2[g]),
        .theta_idx(theta_idx),
        .valid_out(xf_valid[g]), .x_out(xf_x[g]), .y_out(xf_y[g])
      );
    end
  endgenerate

  integer k;
  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 8; k = k + 1) xf_pol_d1[k] <= 1'b0;
    end else begin
      for (k = 0; k < 8; k = k + 1) xf_pol_d1[k] <= ev_pol[k];
    end
  end

  wire [47:0] wr_x_flat, wr_y_flat;
  wire [7:0]  wr_pol_flat;
  generate
    for (g = 0; g < 8; g = g + 1) begin : PACK
      assign wr_x_flat[g*6 +: 6] = xf_x[g];
      assign wr_y_flat[g*6 +: 6] = xf_y[g];
      assign wr_pol_flat[g]      = xf_pol_d1[g];
    end
  endgenerate

  world_mem_writer #(.N_LANES(8), .ADDR_BITS(6)) u_wmem (
    .clk(clk), .rst(rst),
    .wr_valid(xf_valid), .wr_x(wr_x_flat), .wr_y(wr_y_flat), .wr_pol(wr_pol_flat),
    .rd_en(rd_en), .rd_x(rd_x), .rd_y(rd_y),
    .rd_written(rd_written), .rd_pol(rd_pol)
  );
endmodule
