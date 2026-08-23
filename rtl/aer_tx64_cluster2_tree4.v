// N-스케일링 문제(§77: cluster2 처리용량이 N과 무관하게 8개/cycle 고정 -- N=256에서
// N=16 대비 손실 31배)에 대한 새 구조. N=64를 16개씩 4묶음으로 나눠 각자 독립된
// cluster2(무수정, 그대로 인스턴스 4개)를 돌린다. 4묶음은 서로 다른 소스 집합을 전담해서
// 애초에 경쟁하지 않으므로(위쪽 레벨 중재가 필요 없음) 처리용량이 정확히 4배(8→32개/cycle)
// 로 늘어난다 -- 대가는 출력 레인이 8개(핀 4배)로 느는 것.
// 포트는 Genus 기본 read_hdl(-sv 없이)과 호환되도록 unpacked array 대신 flat packed
// 버스로 냄(리프 g의 필드는 row[g*2+:2], col_mask[g*4+:4]).
module aer_tx64_cluster2_tree4 (
  input  wire        clk,
  input  wire        rst,
  input  wire [63:0] req,
  output wire [3:0]  valid0,       // 리프 0~3의 lane0(중심)
  output wire [7:0]  row0_flat,    // 리프별 2비트 x 4
  output wire [15:0] col_mask0_flat, // 리프별 4비트 x 4
  output wire [3:0]  valid1,       // 리프 0~3의 lane1(주변)
  output wire [7:0]  row1_flat,
  output wire [15:0] col_mask1_flat
);
  genvar g;
  generate
    for (g = 0; g < 4; g = g + 1) begin: leaf
      aer_tx16_trad_rowcol_fovea_cluster2 core(
        .clk(clk), .rst(rst), .req(req[g*16 +: 16]),
        .valid0(valid0[g]), .row0(row0_flat[g*2 +: 2]), .col_mask0(col_mask0_flat[g*4 +: 4]),
        .valid1(valid1[g]), .row1(row1_flat[g*2 +: 2]), .col_mask1(col_mask1_flat[g*4 +: 4]));
    end
  endgenerate
endmodule
