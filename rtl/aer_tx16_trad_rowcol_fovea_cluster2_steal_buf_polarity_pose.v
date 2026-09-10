// Pose-tagged extension of the final v1 polarity AER.
//
// Every accepted arrival stores {polarity, pose_version, occurrence_timestamp}
// in the same source-local depth-2 FIFO.  A bitmap packet can contain four
// independently-aged sources, so each column has its own packed metadata:
//   pose_tagsN[col*POSE_W +: POSE_W]
//   time_tagsN[col*TIMESTAMP_W +: TIMESTAMP_W]
// The tags are meaningful only when col_maskN[col] is set.
//
// Admission intentionally remains bit-for-bit compatible with v1: an arrival to
// an already-full source overruns even when that source is granted in the same
// cycle.  This module does not adopt the later v2 full+grant bypass.
module aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose #(
  parameter integer POSE_W = 8,
  parameter integer TIMESTAMP_W = 32
) (
  input                         clk,
  input                         rst,
  input  [15:0]                 arrival,
  input  [15:0]                 polarity_in,
  input  [POSE_W-1:0]           pose_version,
  input  [TIMESTAMP_W-1:0]      occurrence_timestamp,
  output [15:0]                 overrun,
  output reg                    valid0,
  output reg [1:0]              row0,
  output reg [3:0]              col_mask0,
  output reg [3:0]              pol_mask0,
  output reg [(4*POSE_W)-1:0]   pose_tags0,
  output reg [(4*TIMESTAMP_W)-1:0] time_tags0,
  output reg                    valid1,
  output reg [1:0]              row1,
  output reg [3:0]              col_mask1,
  output reg [3:0]              pol_mask1,
  output reg [(4*POSE_W)-1:0]   pose_tags1,
  output reg [(4*TIMESTAMP_W)-1:0] time_tags1
);
  reg [1:0] pending_cnt [0:15];
  reg pol_fifo0 [0:15];
  reg pol_fifo1 [0:15];
  reg [POSE_W-1:0] pose_fifo0 [0:15];
  reg [POSE_W-1:0] pose_fifo1 [0:15];
  reg [TIMESTAMP_W-1:0] time_fifo0 [0:15];
  reg [TIMESTAMP_W-1:0] time_fifo1 [0:15];
  integer pc_k;

  wire [15:0] pending_gt0;
  wire [15:0] pending_full;
  wire [15:0] pol_front_bus;
  wire [(16*POSE_W)-1:0] pose_front_bus;
  wire [(16*TIMESTAMP_W)-1:0] time_front_bus;
  genvar gk;
  generate
    for (gk = 0; gk < 16; gk = gk + 1) begin: gt0
      assign pending_gt0[gk] = (pending_cnt[gk] != 2'd0);
      assign pending_full[gk] = (pending_cnt[gk] == 2'd2);
      assign pol_front_bus[gk] = pol_fifo0[gk];
      assign pose_front_bus[(gk*POSE_W) +: POSE_W] = pose_fifo0[gk];
      assign time_front_bus[(gk*TIMESTAMP_W) +: TIMESTAMP_W] = time_fifo0[gk];
    end
  endgenerate
  assign overrun = arrival & pending_full;

  wire [(4*POSE_W)-1:0] pose_front_row0 = pose_front_bus[(4*POSE_W)-1:0];
  wire [(4*POSE_W)-1:0] pose_front_row1 = pose_front_bus[(8*POSE_W)-1:(4*POSE_W)];
  wire [(4*POSE_W)-1:0] pose_front_row2 = pose_front_bus[(12*POSE_W)-1:(8*POSE_W)];
  wire [(4*POSE_W)-1:0] pose_front_row3 = pose_front_bus[(16*POSE_W)-1:(12*POSE_W)];
  wire [(4*TIMESTAMP_W)-1:0] time_front_row0 = time_front_bus[(4*TIMESTAMP_W)-1:0];
  wire [(4*TIMESTAMP_W)-1:0] time_front_row1 = time_front_bus[(8*TIMESTAMP_W)-1:(4*TIMESTAMP_W)];
  wire [(4*TIMESTAMP_W)-1:0] time_front_row2 = time_front_bus[(12*TIMESTAMP_W)-1:(8*TIMESTAMP_W)];
  wire [(4*TIMESTAMP_W)-1:0] time_front_row3 = time_front_bus[(16*TIMESTAMP_W)-1:(12*TIMESTAMP_W)];

  wire [3:0] row_req;
  assign row_req[0] = |pending_gt0[3:0];
  assign row_req[1] = |pending_gt0[7:4];
  assign row_req[2] = |pending_gt0[11:8];
  assign row_req[3] = |pending_gt0[15:12];

  wire center_r1 = row_req[1];
  wire center_r2 = row_req[2];
  wire periph_r0 = row_req[0];
  wire periph_r3 = row_req[3];
  wire center_idle = ~(center_r1 | center_r2);
  wire periph_idle = ~(periph_r0 | periph_r3);
  wire steal_to_periph = center_idle & periph_r0 & periph_r3;
  wire steal_to_center = periph_idle & center_r1 & center_r2;

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  reg lane0_valid_c;
  reg [1:0] lane0_row_c;
  reg [3:0] lane0_cols_c;
  reg [3:0] lane0_pol_c;
  reg [(4*POSE_W)-1:0] lane0_pose_c;
  reg [(4*TIMESTAMP_W)-1:0] lane0_time_c;
  always @(*) begin
    if (steal_to_center) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd1;
      lane0_cols_c = pending_gt0[7:4];
      lane0_pol_c = pol_front_bus[7:4];
      lane0_pose_c = pose_front_row1;
      lane0_time_c = time_front_row1;
    end else if (~center_idle) begin
      lane0_valid_c = 1'b1;
      lane0_row_c = center_gnt[1] ? 2'd1 : 2'd2;
      lane0_cols_c = center_gnt[1] ? pending_gt0[7:4] : pending_gt0[11:8];
      lane0_pol_c = center_gnt[1] ? pol_front_bus[7:4] : pol_front_bus[11:8];
      lane0_pose_c = center_gnt[1] ? pose_front_row1 : pose_front_row2;
      lane0_time_c = center_gnt[1] ? time_front_row1 : time_front_row2;
    end else if (steal_to_periph) begin
      lane0_valid_c = 1'b1; lane0_row_c = 2'd0;
      lane0_cols_c = pending_gt0[3:0];
      lane0_pol_c = pol_front_bus[3:0];
      lane0_pose_c = pose_front_row0;
      lane0_time_c = time_front_row0;
    end else begin
      lane0_valid_c = 1'b0; lane0_row_c = 2'd0;
      lane0_cols_c = 4'd0; lane0_pol_c = 4'd0; lane0_pose_c = 0; lane0_time_c = 0;
    end
  end

  reg lane1_valid_c;
  reg [1:0] lane1_row_c;
  reg [3:0] lane1_cols_c;
  reg [3:0] lane1_pol_c;
  reg [(4*POSE_W)-1:0] lane1_pose_c;
  reg [(4*TIMESTAMP_W)-1:0] lane1_time_c;
  always @(*) begin
    if (steal_to_periph) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd3;
      lane1_cols_c = pending_gt0[15:12];
      lane1_pol_c = pol_front_bus[15:12];
      lane1_pose_c = pose_front_row3;
      lane1_time_c = time_front_row3;
    end else if (~periph_idle) begin
      lane1_valid_c = 1'b1;
      lane1_row_c = periph_gnt[0] ? 2'd0 : 2'd3;
      lane1_cols_c = periph_gnt[0] ? pending_gt0[3:0] : pending_gt0[15:12];
      lane1_pol_c = periph_gnt[0] ? pol_front_bus[3:0] : pol_front_bus[15:12];
      lane1_pose_c = periph_gnt[0] ? pose_front_row0 : pose_front_row3;
      lane1_time_c = periph_gnt[0] ? time_front_row0 : time_front_row3;
    end else if (steal_to_center) begin
      lane1_valid_c = 1'b1; lane1_row_c = 2'd2;
      lane1_cols_c = pending_gt0[11:8];
      lane1_pol_c = pol_front_bus[11:8];
      lane1_pose_c = pose_front_row2;
      lane1_time_c = time_front_row2;
    end else begin
      lane1_valid_c = 1'b0; lane1_row_c = 2'd0;
      lane1_cols_c = 4'd0; lane1_pol_c = 4'd0; lane1_pose_c = 0; lane1_time_c = 0;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; pol_mask0 <= 4'd0; pose_tags0 <= 0; time_tags0 <= 0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; pol_mask1 <= 4'd0; pose_tags1 <= 0; time_tags1 <= 0;
    end else begin
      valid0 <= lane0_valid_c; row0 <= lane0_row_c;
      col_mask0 <= lane0_cols_c; pol_mask0 <= lane0_pol_c;
      pose_tags0 <= lane0_pose_c; time_tags0 <= lane0_time_c;
      valid1 <= lane1_valid_c; row1 <= lane1_row_c;
      col_mask1 <= lane1_cols_c; pol_mask1 <= lane1_pol_c;
      pose_tags1 <= lane1_pose_c; time_tags1 <= lane1_time_c;
    end
  end

  wire [15:0] granted_bitmap =
    (lane0_valid_c ? (lane0_cols_c << (lane0_row_c*4)) : 16'd0) |
    (lane1_valid_c ? (lane1_cols_c << (lane1_row_c*4)) : 16'd0);

  always @(posedge clk) begin
    if (rst) begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        pending_cnt[pc_k] <= 2'd0;
        pol_fifo0[pc_k] <= 1'b0;
        pol_fifo1[pc_k] <= 1'b0;
        pose_fifo0[pc_k] <= 0;
        pose_fifo1[pc_k] <= 0;
        time_fifo0[pc_k] <= 0;
        time_fifo1[pc_k] <= 0;
      end
    end else begin
      for (pc_k = 0; pc_k < 16; pc_k = pc_k + 1) begin
        case ({arrival[pc_k] && !pending_full[pc_k], granted_bitmap[pc_k]})
          2'b10: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k] + 2'd1;
            if (pending_cnt[pc_k] == 2'd0) begin
              pol_fifo0[pc_k] <= polarity_in[pc_k];
              pose_fifo0[pc_k] <= pose_version;
              time_fifo0[pc_k] <= occurrence_timestamp;
            end else begin
              pol_fifo1[pc_k] <= polarity_in[pc_k];
              pose_fifo1[pc_k] <= pose_version;
              time_fifo1[pc_k] <= occurrence_timestamp;
            end
          end
          2'b01: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k] - 2'd1;
            pol_fifo0[pc_k] <= pol_fifo1[pc_k];
            pose_fifo0[pc_k] <= pose_fifo1[pc_k];
            time_fifo0[pc_k] <= time_fifo1[pc_k];
          end
          2'b11: begin
            pending_cnt[pc_k] <= pending_cnt[pc_k];
            pol_fifo0[pc_k] <= polarity_in[pc_k];
            pose_fifo0[pc_k] <= pose_version;
            time_fifo0[pc_k] <= occurrence_timestamp;
          end
          default: pending_cnt[pc_k] <= pending_cnt[pc_k];
        endcase
      end
    end
  end
endmodule
