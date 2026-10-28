// Digital 2차 통합 top, 1024각도/1024x1024 월드 타겟 변형 -- v1(256각도 RMCM 표, 64x64)과 같은 구조에서
// 좌표 변환 8레인을 **직접 행렬곱(coord_transform_rotate2d_1024)**으로 바꾼 것.
// 이유(progress.md §227/§231): 1024각도(입력 16,384가지)에서는 표(RMCM)가 합성 3.7배, 배치배선 후 4.6배 크고
// 배선이 안 풀려(DRC 1만+, setup -20.9 ns) 직접 행렬곱(7,354 um2, DRC 0, setup -0.099 ns @5.0 ns)이 우세.
// 변경점: theta_idx 8 -> 10비트(자세 FIFO 폭 W=10, *_pose_w.v), 좌표 6 -> 10비트, world_addr 12 -> 20비트({y,x}).
// 저장소는 v1과 같이 이 파일 밖(외부 SRAM 스타일 단일 쓰기 포트) -- 1024x1024x2비트는 SRAM 매크로로 붙여야 함.
module aer_tx16_coord_transform_mul1024 (
  input         clk,
  input         rst,
  input  [15:0] arrival,
  input  [15:0] polarity_in,
  input  [9:0]  theta_idx,     // 지금 이 순간의 세계 회전각(발생시점 태깅용, 1024단계)
  output [15:0] overrun,
  output [7:0]  wmem_overrun,

  output              world_we,
  output [19:0]       world_addr,   // {y[9:0], x[9:0]}
  output              world_pol
);
  localparam integer W = 10;

  wire        valid0, valid1;
  wire [1:0]  row0, row1;
  wire [3:0]  col_mask0, col_mask1, pol_mask0, pol_mask1;
  wire [4*W-1:0] pose_mask0, pose_mask1;

  wire wmem_stall;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose_w #(.W(W)) u_tx (
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
  wire [W-1:0]      ev_theta [0:7];

  genvar g;
  generate
    for (g = 0; g < 4; g = g + 1) begin : DECODE0
      assign ev_valid[g]  = valid0 & col_mask0[g];
      assign ev_xc2[g]    = 2*g - 3;
      assign ev_yc2[g]    = 2*row0 - 3;
      assign ev_pol[g]    = pol_mask0[g];
      assign ev_theta[g]  = pose_mask0[g*W +: W];
    end
    for (g = 0; g < 4; g = g + 1) begin : DECODE1
      assign ev_valid[4+g] = valid1 & col_mask1[g];
      assign ev_xc2[4+g]   = 2*g - 3;
      assign ev_yc2[4+g]   = 2*row1 - 3;
      assign ev_pol[4+g]   = pol_mask1[g];
      assign ev_theta[4+g] = pose_mask1[g*W +: W];
    end
  endgenerate

  wire [7:0] xf_valid;
  wire [9:0] xf_x [0:7];
  wire [9:0] xf_y [0:7];
  reg        xf_pol_d1 [0:7];

  generate
    for (g = 0; g < 8; g = g + 1) begin : XFORM
      coord_transform_rotate2d_1024 u_xf (
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

  wire [79:0] wr_x_flat, wr_y_flat;
  wire [7:0]  wr_pol_flat;
  generate
    for (g = 0; g < 8; g = g + 1) begin : PACK
      assign wr_x_flat[g*10 +: 10] = xf_x[g];
      assign wr_y_flat[g*10 +: 10] = xf_y[g];
      assign wr_pol_flat[g]        = xf_pol_d1[g];
    end
  endgenerate

  world_mem_writer #(.N_LANES(8), .ADDR_BITS(10)) u_wmem (
    .clk(clk), .rst(rst),
    .wr_valid(xf_valid), .wr_x(wr_x_flat), .wr_y(wr_y_flat), .wr_pol(wr_pol_flat),
    .wr_overrun(wmem_overrun), .stall(wmem_stall),
    .world_we(world_we), .world_addr(world_addr), .world_pol(world_pol)
  );
endmodule
