// Delay-Shadow AER(5번 문제 재도전) — jitter를 없애려 하지 않고, 각 grant가 "이번에
// 경합에서 밀렸다가 다음에 이긴 것"인지(q=1)와 "바로 이겼다"(q=0)인지를 관측해서
// 그대로 실어보낸다. row-trim(§86)이 찾은 죽은 code space(레인당 row 필드 2비트 중
// 1비트만 실제 필요)를 그대로 재사용 -- 남는 1비트에 row selector 대신 delay shadow
// bit q를 실어서 **link width 증가가 0**이다(row-trim처럼 줄이는 게 아니라, 이미
// 절약되는 자리에 새 정보를 채워넣는 것).
//
// q 판정: 레인 안에서 두 row가 동시에 요청했는데 이번에 못 이긴 쪽은 "waiting" 플래그가
// 서고, 다음에 그 row가 이길 때 waiting이었으면 q=1(경합 때문에 한 사이클 밀렸다는 뜻),
// 처음부터 경합 없이 이겼으면 q=0. 판정은 row 단위(한 grant가 col_mask로 여러 열을
// 동시에 담아도 그 grant 전체가 같은 지연을 겪으므로 비트 1개로 충분 -- 문서 §12.4).
module aer_cluster2_delay_shadow_encode (
  input  wire        clk,
  input  wire        rst,
  input  wire [15:0] req,      // cluster2에 넣는 것과 동일한 신호(외부에서 관찰)
  input  wire        valid0,
  input  wire [1:0]  row0,     // cluster2 native 출력, 항상 2'd1 또는 2'd2
  input  wire [3:0]  col_mask0,
  input  wire        valid1,
  input  wire [1:0]  row1,     // cluster2 native 출력, 항상 2'd0 또는 2'd3
  input  wire [3:0]  col_mask1,
  output wire        out_valid0,
  output wire [1:0]  packed_row0,  // {row_select, q}
  output wire [3:0]  out_col_mask0,
  output wire        out_valid1,
  output wire [1:0]  packed_row1,
  output wire [3:0]  out_col_mask1
);
  wire row_req0 = |req[3:0];
  wire row_req1 = |req[7:4];
  wire row_req2 = |req[11:8];
  wire row_req3 = |req[15:12];

  reg wait1, wait2; // center lane(row1,row2) 대기 플래그
  reg wait0, wait3; // periph lane(row0,row3) 대기 플래그

  wire q0 = valid0 ? ((row0 == 2'd1) ? wait1 : wait2) : 1'b0;
  wire q1 = valid1 ? ((row1 == 2'd0) ? wait0 : wait3) : 1'b0;

  assign out_valid0 = valid0;
  assign packed_row0 = {(row0 == 2'd2), q0};
  assign out_col_mask0 = col_mask0;
  assign out_valid1 = valid1;
  assign packed_row1 = {(row1 == 2'd3), q1};
  assign out_col_mask1 = col_mask1;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      wait1 <= 1'b0; wait2 <= 1'b0; wait0 <= 1'b0; wait3 <= 1'b0;
    end else begin
      if (valid0 && row0 == 2'd1) wait1 <= 1'b0;
      else if (row_req1 && valid0 && row0 == 2'd2) wait1 <= 1'b1;
      else if (!row_req1) wait1 <= 1'b0;

      if (valid0 && row0 == 2'd2) wait2 <= 1'b0;
      else if (row_req2 && valid0 && row0 == 2'd1) wait2 <= 1'b1;
      else if (!row_req2) wait2 <= 1'b0;

      if (valid1 && row1 == 2'd0) wait0 <= 1'b0;
      else if (row_req0 && valid1 && row1 == 2'd3) wait0 <= 1'b1;
      else if (!row_req0) wait0 <= 1'b0;

      if (valid1 && row1 == 2'd3) wait3 <= 1'b0;
      else if (row_req3 && valid1 && row1 == 2'd0) wait3 <= 1'b1;
      else if (!row_req3) wait3 <= 1'b0;
    end
  end
endmodule
