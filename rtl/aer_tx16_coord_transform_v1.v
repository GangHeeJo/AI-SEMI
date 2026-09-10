// Digital 2차 1단계 통합 top -- steal_buf_polarity_pose(1차 TX + occurrence-pose 태깅, 최대
// 8 events/cycle) -> 로컬(row,col) 디코드 -> coord_transform_rmcm(8레인 병렬, 채택안) ->
// world_mem_writer(FIFO+arbiter8로 SRAM 단일 포트에 직렬화).
//
// v2(2026-09-10): theta_idx는 이제 "지금 이 순간의 세계 회전각"이지만, coord_transform_rmcm에
// 직접 먹이지 않고 TX의 theta_idx_in으로 먼저 들어가 **이벤트가 도착한 바로 그 순간** 소스별
// pose_fifo에 극성과 나란히 저장된다(v1의 문제였던 "배출 시점 theta 사용" 캐베앗을 근본적으로
// 해결 -- progress.md §111/§113 참고). coord_transform_rmcm은 이제 배출된 pose_mask(발생시점
// theta)를 쓴다.
//
// 저장소는 이 파일 밖에 있음(world_mem_writer가 SRAM 스타일 단일 포트(world_we/addr/pol)만
// 노출, 실제 저장소는 시뮬레이션 메모리 모델/BRAM/SRAM 매크로).
module aer_tx16_coord_transform_v1 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  input  [7:0]  theta_idx,     // 지금 이 순간의 세계 회전각(발생시점 태깅용)
  output [15:0] overrun,
  output [7:0]  wmem_overrun,

  output              world_we,
  output [11:0]       world_addr,
  output              world_pol
);
  wire        valid0, valid1;
  wire [1:0]  row0, row1;
  wire [3:0]  col_mask0, col_mask1, pol_mask0, pol_mask1;
  wire [31:0] pose_mask0, pose_mask1;

  wire wmem_stall;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose u_tx (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx_in({16{theta_idx}}),
    .stall(wmem_stall),
    .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .pol_mask0(pol_mask0), .pose_mask0(pose_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .pol_mask1(pol_mask1), .pose_mask1(pose_mask1)
  );

  // lane 0~3 = row0의 col 0~3, lane 4~7 = row1의 col 0~3
  wire [7:0]        ev_valid;
  wire signed [3:0] ev_xc2 [0:7];
  wire signed [3:0] ev_yc2 [0:7];
  wire              ev_pol   [0:7];
  wire [7:0]        ev_theta [0:7];

  genvar g;
  generate
    for (g = 0; g < 4; g = g + 1) begin : DECODE0
      assign ev_valid[g]  = valid0 & col_mask0[g];
      assign ev_xc2[g]    = 2*g - 3;
      assign ev_yc2[g]    = 2*row0 - 3;
      assign ev_pol[g]    = pol_mask0[g];
      assign ev_theta[g]  = pose_mask0[g*8 +: 8];
    end
    for (g = 0; g < 4; g = g + 1) begin : DECODE1
      assign ev_valid[4+g] = valid1 & col_mask1[g];
      assign ev_xc2[4+g]   = 2*g - 3;
      assign ev_yc2[4+g]   = 2*row1 - 3;
      assign ev_pol[4+g]   = pol_mask1[g];
      assign ev_theta[4+g] = pose_mask1[g*8 +: 8];
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
        .theta_idx(ev_theta[g]),
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
    .wr_overrun(wmem_overrun), .stall(wmem_stall),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );
endmodule
