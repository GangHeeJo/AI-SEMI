// cluster2 + 진짜 Global Hold(Ryu Gen3 방식) -- 주기적으로(HOLD_PERIOD cycle마다)
// 현재 pending 상태를 "배치 스냅샷"에 얼려넣고, 그 스냅샷 안에서만 서비스한다.
// 스냅샷 경계 사이에 새로 도착한 이벤트는 실제 req는 즉시 뜨지만 batch_snapshot에는
// 안 들어가서(다음 경계까지 대기), 중재는 항상 "얼려진 그림"만 본다 -- TDM(§68)과
// 다르게 "스케줄이 고정"이 아니라 "무엇을 볼 수 있는지가 고정"이라는 게 핵심.
// 그랜트된 소스는 즉시 배치에서 빠짐(sticky 방지) -- 다음 경계 전에 같은 소스가 또
// 도착해도(재발화) 그 즉시 재편입되지 않고 다음 경계까지 기다림(진짜 스냅샷 의미론).
module aer_tx16_trad_rowcol_fovea_cluster2_globalhold #(
  parameter HOLD_PERIOD = 4
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1
);
  reg [15:0] batch_snapshot;
  reg [31:0] phase_cnt;

  wire [15:0] visible_req = batch_snapshot & req;

  wire [3:0] row_req;
  assign row_req[0] = |visible_req[3:0];
  assign row_req[1] = |visible_req[7:4];
  assign row_req[2] = |visible_req[11:8];
  assign row_req[3] = |visible_req[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;
  wire [3:0] center_req_in = row_req & CENTER_MASK;
  wire [3:0] periph_req_in = row_req & PERIPH_MASK;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_center_cols, sel_periph_cols;
  always @(*) begin
    case (idx4(center_gnt))
      2'd0: sel_center_cols = visible_req[3:0];
      2'd1: sel_center_cols = visible_req[7:4];
      2'd2: sel_center_cols = visible_req[11:8];
      default: sel_center_cols = visible_req[15:12];
    endcase
    case (idx4(periph_gnt))
      2'd0: sel_periph_cols = visible_req[3:0];
      2'd1: sel_periph_cols = visible_req[7:4];
      2'd2: sel_periph_cols = visible_req[11:8];
      default: sel_periph_cols = visible_req[15:12];
    endcase
  end

  wire [15:0] granted_bitmap =
    (|center_gnt ? (sel_center_cols << (idx4(center_gnt)*4)) : 16'd0) |
    (|periph_gnt ? (sel_periph_cols << (idx4(periph_gnt)*4)) : 16'd0);

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0;
    end else begin
      valid0 <= |center_gnt; row0 <= idx4(center_gnt); col_mask0 <= sel_center_cols;
      valid1 <= |periph_gnt; row1 <= idx4(periph_gnt); col_mask1 <= sel_periph_cols;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      batch_snapshot <= 16'd0;
      phase_cnt <= 32'd0;
    end else begin
      if (phase_cnt == HOLD_PERIOD-1) begin
        phase_cnt <= 32'd0;
        batch_snapshot <= (batch_snapshot & ~granted_bitmap) | req;
      end else begin
        phase_cnt <= phase_cnt + 32'd1;
        batch_snapshot <= batch_snapshot & ~granted_bitmap;
      end
    end
  end
endmodule
