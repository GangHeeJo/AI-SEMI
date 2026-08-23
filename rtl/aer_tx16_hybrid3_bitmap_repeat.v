// 3-way 결합: cluster2(주소기반) + dense bitmap(§70, 넓은 동시부하) + repeat압축
// (§74, 집중/반복 트래픽). bitmap이 활성 행 3개 이상인 넓은 트래픽을 먼저 걸러가므로,
// addressed 모드에 남는 트래픽은 상대적으로 집중형(재발화) 비중이 높아져 repeat압축의
// 손익비가 단독일 때보다 나아질 수 있다는 가설을 검증한다. bitmap 자체엔 repeat압축을
// 얹지 않음(활성 행이 많을 때 정확히 같은 bitmap이 반복될 확률은 낮아 보임, §74 데이터
// 기준 넓은 트래픽일수록 repeat_hits 비율이 낮았음).
module aer_tx16_hybrid3_bitmap_repeat #(
  parameter ROW_THRESHOLD = 2   // active_rows > ROW_THRESHOLD 이면 bitmap 전환
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        mode,        // 0=addressed, 1=dense bitmap
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        repeat0,     // mode=0일 때만 유효
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg        repeat1,     // mode=0일 때만 유효
  output reg [15:0] bitmap
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

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
      2'd0: sel_center_cols = req[3:0];
      2'd1: sel_center_cols = req[7:4];
      2'd2: sel_center_cols = req[11:8];
      default: sel_center_cols = req[15:12];
    endcase
    case (idx4(periph_gnt))
      2'd0: sel_periph_cols = req[3:0];
      2'd1: sel_periph_cols = req[7:4];
      2'd2: sel_periph_cols = req[11:8];
      default: sel_periph_cols = req[15:12];
    endcase
  end

  wire [2:0] active_rows = row_req[0] + row_req[1] + row_req[2] + row_req[3];
  wire use_bitmap = (active_rows > ROW_THRESHOLD[2:0]);

  wire new_valid0 = |center_gnt;
  wire [1:0] new_row0 = idx4(center_gnt);
  wire [3:0] new_colmask0 = sel_center_cols;
  wire new_valid1 = |periph_gnt;
  wire [1:0] new_row1 = idx4(periph_gnt);
  wire [3:0] new_colmask1 = sel_periph_cols;

  // repeat 비교 기준(직전 유효 grant, addressed 모드였을 때만) -- bitmap 모드로
  // 전환됐다 돌아와도 sticky하게 유지(§74와 동일 원칙: gap을 무시하고 마지막 주소 기억).
  reg last_valid0, last_valid1;
  reg [1:0] last_row0, last_row1;
  reg [3:0] last_colmask0, last_colmask1;

  always @(posedge clk) begin
    if (rst) begin
      mode <= 1'b0;
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; repeat0 <= 1'b0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; repeat1 <= 1'b0;
      bitmap <= 16'd0;
      last_valid0 <= 1'b0; last_row0 <= 2'd0; last_colmask0 <= 4'd0;
      last_valid1 <= 1'b0; last_row1 <= 2'd0; last_colmask1 <= 4'd0;
    end else begin
      mode <= use_bitmap;
      if (use_bitmap) begin
        bitmap <= req;
        valid0 <= 1'b0; repeat0 <= 1'b0;
        valid1 <= 1'b0; repeat1 <= 1'b0;
        // bitmap 모드 사이클엔 addressed 쪽 grant가 없으니 last_* 갱신 없음(sticky 유지)
      end else begin
        bitmap <= 16'd0;
        repeat0 <= new_valid0 && last_valid0 && (new_row0 == last_row0) && (new_colmask0 == last_colmask0);
        valid0 <= new_valid0; row0 <= new_row0; col_mask0 <= new_colmask0;
        if (new_valid0) begin
          last_valid0 <= 1'b1; last_row0 <= new_row0; last_colmask0 <= new_colmask0;
        end

        repeat1 <= new_valid1 && last_valid1 && (new_row1 == last_row1) && (new_colmask1 == last_colmask1);
        valid1 <= new_valid1; row1 <= new_row1; col_mask1 <= new_colmask1;
        if (new_valid1) begin
          last_valid1 <= 1'b1; last_row1 <= new_row1; last_colmask1 <= new_colmask1;
        end
      end
    end
  end
endmodule
