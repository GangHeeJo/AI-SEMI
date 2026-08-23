// cluster2 + 연속 동일주소 반복압축(1번, 새 축) -- §72에서 확인했듯 retrigger/
// elephant_mouse는 admission 게이트 한계로 "손실"은 못 고치지만, "이미 배달된
// 이벤트들의 비트비용"은 다른 문제다. 이번 그랜트의 (row,col_mask)가 직전 그랜트와
// 완전히 같으면(같은 소스가 레인을 계속 이기는 상황, elephant/retrigger의 실제 패턴)
// 1비트 repeat 플래그만 내보내고, 수신측은 자기가 캐싱해둔 직전 주소를 재사용한다고
// 가정 -- 실제 주소 필드(row/col_mask)는 회로엔 그대로 남지만(레지스터 갱신은 그대로),
// TB가 "repeat=1이면 1비트만, 0이면 6비트(row2+colmask4)+flag1=7비트" 식으로 실제
// 전송 비트를 센다(§69/§70과 동일한 회계 방식).
module aer_tx16_trad_rowcol_fovea_cluster2_repeat (
  input         clk,
  input         rst,
  input  [15:0] req,
  output reg        valid0,
  output reg [1:0]  row0,
  output reg [3:0]  col_mask0,
  output reg        repeat0,   // 1이면 row0/col_mask0가 직전 그랜트와 동일(수신측 캐시 재사용)
  output reg        valid1,
  output reg [1:0]  row1,
  output reg [3:0]  col_mask1,
  output reg        repeat1
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

  wire new_valid0 = |center_gnt;
  wire [1:0] new_row0 = idx4(center_gnt);
  wire [3:0] new_colmask0 = sel_center_cols;
  wire new_valid1 = |periph_gnt;
  wire [1:0] new_row1 = idx4(periph_gnt);
  wire [3:0] new_colmask1 = sel_periph_cols;

  // "직전 사이클"이 아니라 "마지막으로 유효했던 그랜트"와 비교(사이 유휴 사이클이
  // 껴도 sticky하게 유지) -- admission 지연으로 재발화가 admit/reject를 오가며 gap이
  // 생겨도(§72), 그 사이 gap을 무시하고 "같은 주소가 다시 왔다"를 잡아내기 위함.
  reg last_valid0, last_valid1;
  reg [1:0] last_row0, last_row1;
  reg [3:0] last_colmask0, last_colmask1;

  always @(posedge clk) begin
    if (rst) begin
      valid0 <= 1'b0; row0 <= 2'd0; col_mask0 <= 4'd0; repeat0 <= 1'b0;
      valid1 <= 1'b0; row1 <= 2'd0; col_mask1 <= 4'd0; repeat1 <= 1'b0;
      last_valid0 <= 1'b0; last_row0 <= 2'd0; last_colmask0 <= 4'd0;
      last_valid1 <= 1'b0; last_row1 <= 2'd0; last_colmask1 <= 4'd0;
    end else begin
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
endmodule
