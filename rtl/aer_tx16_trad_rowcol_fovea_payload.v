// fovea에 페이로드(payload) 필드를 추가한 변형 -- "위치만" 보내는 고전 AER에서
// "위치+임의 데이터"를 보내는 현수/준영 스타일 인터페이스로 확장했을 때 진짜 비용이
// 얼마인지 측정하려는 실험. 중재 로직(행/열 선택)은 fovea와 완전히 동일 -- 딱 하나,
// 이긴 소스의 데이터를 뽑아오는 16:1 멀티플렉서만 추가됨.
module aer_tx16_trad_rowcol_fovea_payload #(
  parameter WEIGHT = 5,
  parameter DATA_WIDTH = 16
) (
  input         clk,
  input         rst,
  input  [15:0] req,
  input  [16*DATA_WIDTH-1:0] data_in, // source i 페이로드 = data_in[i*DATA_WIDTH +: DATA_WIDTH]
  output reg        valid,
  output reg [3:0]  addr,
  output reg [DATA_WIDTH-1:0] data_out
);
  wire [3:0] row_req;
  assign row_req[0] = |req[3:0];
  assign row_req[1] = |req[7:4];
  assign row_req[2] = |req[11:8];
  assign row_req[3] = |req[15:12];

  localparam [3:0] CENTER_MASK = 4'b0110;
  localparam [3:0] PERIPH_MASK = 4'b1001;

  localparam RW = (WEIGHT == 0) ? 1 : $clog2(WEIGHT + 1);
  reg [RW-1:0] round;
  wire prefer_center = (round != WEIGHT[RW-1:0]);

  wire center_avail = |(row_req & CENTER_MASK);
  wire periph_avail = |(row_req & PERIPH_MASK);
  wire use_center = (prefer_center && center_avail) || (!prefer_center && !periph_avail && center_avail);
  wire use_periph = (!prefer_center && periph_avail) || (prefer_center && !center_avail && periph_avail);

  wire [3:0] center_req_in = use_center ? (row_req & CENTER_MASK) : 4'b0000;
  wire [3:0] periph_req_in = use_periph ? (row_req & PERIPH_MASK) : 4'b0000;
  wire [3:0] center_gnt, periph_gnt;

  arbiter4_tree center_arb(.clk(clk), .rst(rst), .req(center_req_in), .gnt(center_gnt));
  arbiter4_tree periph_arb(.clk(clk), .rst(rst), .req(periph_req_in), .gnt(periph_gnt));

  wire [3:0] row_gnt = use_center ? center_gnt : (use_periph ? periph_gnt : 4'b0000);

  function [1:0] idx4;
    input [3:0] bits;
    begin
      if (bits[0]) idx4 = 2'd0;
      else if (bits[1]) idx4 = 2'd1;
      else if (bits[2]) idx4 = 2'd2;
      else idx4 = 2'd3;
    end
  endfunction

  reg [3:0] sel_row_cols;
  always @(*) begin
    case (idx4(row_gnt))
      2'd0: sel_row_cols = req[3:0];
      2'd1: sel_row_cols = req[7:4];
      2'd2: sel_row_cols = req[11:8];
      default: sel_row_cols = req[15:12];
    endcase
  end

  wire [3:0] col_gnt;
  arbiter4_tree col_arb(.clk(clk), .rst(rst), .req(sel_row_cols), .gnt(col_gnt));

  // NEW: 이긴 소스(row*4+col)의 페이로드를 16:1로 뽑아옴 -- 추가된 부분은 이 멀티
  // 플렉서 하나뿐, 중재 로직 자체는 손대지 않음.
  wire [3:0] winning_source = {idx4(row_gnt), idx4(col_gnt)};
  wire [DATA_WIDTH-1:0] sel_data = data_in[winning_source*DATA_WIDTH +: DATA_WIDTH];

  always @(posedge clk) begin
    if (rst) begin
      round <= {RW{1'b0}};
    end else if (|row_gnt) begin
      round <= (round == WEIGHT[RW-1:0]) ? {RW{1'b0}} : round + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      valid    <= 1'b0;
      addr     <= 4'd0;
      data_out <= {DATA_WIDTH{1'b0}};
    end else begin
      valid    <= |row_gnt;
      addr     <= {idx4(row_gnt), idx4(col_gnt)};
      data_out <= sel_data;
    end
  end
endmodule
