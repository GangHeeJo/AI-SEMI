// Digital 2차 2단계 predictor -- scripts/bayes_filter_fixed_model.py:run_bayes_filter_fixed()의
// 고정소수점 오라클(§131/132에서 확정: avg-optimized alpha=2, eps_shift=8)을 RTL로 그대로 재현.
// 이벤트를 하나씩(row,col,pol) 받아 256개 theta 후보에 대한 belief를 갱신하고, 이번 이벤트의
// MAP theta를 추정해 내놓는다 -- 그 theta가 aer_tx16_coord_transform_v1의 theta_idx 입력으로
// 흘러들어가 1단계 좌표변환에 쓰인다(두 모듈은 이 predictor가 만드는 theta_idx로 연결됨,
// 아직 top-level 통합은 안 함).
//
// 오라클과 정확히 같은 두 단계 순차처리(diffuse 전체 스윕 -> likelihood 전체 스윕)를 그대로
// 따른다 -- 이웃(diffuse)은 스윕 도중 옛 값을 읽어야 해서 더블버퍼(belief_mem[0]/[1], bank로
// 스왑) 필요, likelihood는 자기 자신만 보므로 in-place. 이벤트 하나당 대략 256(diffuse) +
// 256(likelihood) [+ 256(renorm, 드묾) 또는 256(collapse, §132 실측 20곳에서 0회 발생)] +
// 소수 사이클 -- world_mem_writer가 담당하는 초당 수천 이벤트급 전송경로와 달리, 이 predictor는
// "천천히 갱신되는 전역 theta_idx"를 만드는 역할이라 이 정도 지연은 아키텍처상 문제 없음
// (aer_tx16_coord_transform_v1의 theta_idx 포트가 이미 "그 순간의 전역값을 샘플링"하는 방식).
//
// world memory(칸별 on/off 관측횟수)는 이 모듈 안에 4096칸(64x64) 전부 내장했다(world_mem_writer
// 계열처럼 포트만 노출하고 저장소를 밖에 두는 관례와 다름) -- predictor 자신의 판단(다음 likelihood
// 평가)에 매 이벤트 다시 쓰이는 사적 상태라 외부에 SRAM 매크로로 떼어내는 건 검증 이후 PPA
// 단계에서 결정.
// ponytail: cnt_on/cnt_off를 4096개 레지스터로 합성하면 비쌀 수 있음 -- SRAM 매크로 포트로
// 빼내는 리팩터는 PPA 실측 후 필요하면 진행(world_mem_writer가 이미 겪은 v1->v3 경로와 동일 패턴).
module bayes_filter #(
  parameter integer EPS_SHIFT   = 8,          // diffuse_eps ~= 2^-EPS_SHIFT (§132: 8 확정)
  parameter integer BELIEF_BITS = 32,
  parameter integer LIKE_BITS   = 8,
  parameter integer CNT_MAX     = 15          // 4비트 포화 카운터
)(
  input                     clk,
  input                     rst,
  input                     valid_in,
  input  [1:0]              row_in,
  input  [1:0]              col_in,
  input                     pol_in,
  output                    busy,
  output reg                valid_out,        // 1사이클 펄스: theta_out이 이번 이벤트의 MAP theta
  output reg [7:0]          theta_out
);
  `include "rtl/coord_transform_rmcm_lut.vh"
  `include "rtl/bayes_filter_like_lut.vh"

  localparam [BELIEF_BITS-1:0] BELIEF_INIT = {1'b1, {(BELIEF_BITS-4){1'b0}}}; // 1<<(BITS-4)
  localparam [BELIEF_BITS-1:0] RENORM_LOW  = {1'b1, {16{1'b0}}};              // 1<<16
  localparam [BELIEF_BITS-1:0] COLLAPSE_VAL = BELIEF_INIT >> 8;

  localparam ST_CLEAR       = 0,
             ST_IDLE        = 1,
             ST_DIFFUSE     = 2,
             ST_LIKE        = 3,
             ST_COLLAPSE    = 4,
             ST_RENORM_CALC = 5,
             ST_RENORM_APPLY= 6,
             ST_COMMIT      = 7;
  reg [2:0] state;

  // 256개 theta belief, 더블버퍼(diffuse가 이웃의 옛 값을 읽어야 해서 필요)
  reg [BELIEF_BITS-1:0] belief_mem [0:1][0:255];
  reg                   bank;      // 0/1 -- belief_mem[bank]가 "현재" 값

  // world memory(칸별 관측횟수), 64x64=4096칸
  reg [3:0] cnt_on  [0:4095];
  reg [3:0] cnt_off [0:4095];

  reg [1:0] row_r, col_r;
  reg       pol_r;
  reg [11:0] clr_idx;  // ST_CLEAR: 0~4095
  reg [7:0] idx;       // ST_DIFFUSE/LIKE/COLLAPSE/RENORM_APPLY: 0~255
  reg [BELIEF_BITS-1:0] max_b;
  reg [7:0] map_theta;
  reg [5:0] map_x, map_y;
  reg [4:0] shift_amt;

  assign busy = (state != ST_IDLE) && (state != ST_CLEAR);

  // diffuse 입력(이웃, 현재 bank의 옛 값)
  wire [7:0] idx_prev = (idx == 8'd0)   ? 8'd255 : idx - 8'd1;
  wire [7:0] idx_next = (idx == 8'd255) ? 8'd0   : idx + 8'd1;
  wire [BELIEF_BITS-1:0] b_c = belief_mem[bank][idx];
  wire [BELIEF_BITS-1:0] b_l = belief_mem[bank][idx_prev];
  wire [BELIEF_BITS-1:0] b_r = belief_mem[bank][idx_next];
  wire [BELIEF_BITS-1:0] diffused = b_c - (2 * (b_c >> EPS_SHIFT)) + (b_l >> EPS_SHIFT) + (b_r >> EPS_SHIFT);

  // likelihood 입력(현재 bank, 자기 자신만 봄)
  wire [11:0] xy   = coord_transform_rmcm_lut(row_r, col_r, idx);
  wire [5:0]  lx   = xy[11:6];
  wire [5:0]  ly   = xy[5:0];
  wire [11:0] addr = {lx, ly};
  wire [3:0]  n_on  = cnt_on[addr];
  wire [3:0]  n_off = cnt_off[addr];
  wire [7:0]  like  = bayes_filter_like_lut(n_on, n_off, pol_r);
  wire [BELIEF_BITS+LIKE_BITS-1:0] prod = belief_mem[bank][idx] * like;
  wire [BELIEF_BITS-1:0] liked = prod >> LIKE_BITS;
  // idx==255 사이클 자신의 값까지 합친 "진짜" 최종 max_b -- collapse/renorm 결정에 씀
  // (레지스터 max_b만 보면 이 사이클의 갱신이 아직 반영 전이라 틀릴 수 있음, 위 ST_LIKE 참고).
  wire [BELIEF_BITS-1:0] eff_max_b = (liked > max_b) ? liked : max_b;

  // renorm 판단
  wire renorm_step_done = ((max_b << (shift_amt + 1)) >= BELIEF_INIT) || (shift_amt == 5'd31);

  // COMMIT 대상 칸
  wire [11:0] commit_addr = {map_x, map_y};
  wire [3:0]  c_on  = cnt_on[commit_addr];
  wire [3:0]  c_off = cnt_off[commit_addr];

  integer bi;
  always @(posedge clk) begin
    if (rst) begin
      state <= ST_CLEAR;
      clr_idx <= 12'd0;
      bank <= 1'b0;
      valid_out <= 1'b0;
      theta_out <= 8'd0;
      max_b <= {BELIEF_BITS{1'b0}};
      map_theta <= 8'd0;
      map_x <= 6'd0; map_y <= 6'd0;
      for (bi = 0; bi < 256; bi = bi + 1) belief_mem[0][bi] <= (bi == 0) ? BELIEF_INIT : {BELIEF_BITS{1'b0}};
    end else begin
      valid_out <= 1'b0;
      case (state)
        ST_CLEAR: begin
          cnt_on[clr_idx]  <= 4'd0;
          cnt_off[clr_idx] <= 4'd0;
          if (clr_idx == 12'd4095) state <= ST_IDLE;
          else clr_idx <= clr_idx + 12'd1;
        end

        ST_IDLE: begin
          if (valid_in) begin
            row_r <= row_in; col_r <= col_in; pol_r <= pol_in;
            idx <= 8'd0;
            state <= ST_DIFFUSE;
          end
        end

        ST_DIFFUSE: begin
          belief_mem[~bank][idx] <= diffused;
          if (idx == 8'd255) begin
            bank <= ~bank;
            idx <= 8'd0;
            max_b <= {BELIEF_BITS{1'b0}};
            map_theta <= 8'd0;
            map_x <= 6'd0; map_y <= 6'd0;
            state <= ST_LIKE;
          end else idx <= idx + 8'd1;
        end

        ST_LIKE: begin
          belief_mem[bank][idx] <= liked;
          if (liked > max_b) begin
            max_b <= liked;
            map_theta <= idx;
            map_x <= lx; map_y <= ly;
          end
          if (idx == 8'd255) begin
            // python처럼 두 검사(collapse, renorm)를 순서대로: collapse면 renorm 조건이
            // 자동으로 거짓이 되는 파라미터 관계(COLLAPSE_VAL=2^20 > RENORM_LOW=2^16)라
            // collapse 후 renorm 재검사는 생략(§132 실측 20곳에서 collapse 자체가 0회).
            //
            // 버그였다가 고침: 이 idx==255 사이클 자체에서 `max_b<=liked`가 논블로킹으로
            // 걸릴 수 있는데, 바로 아래 비교가 레지스터 `max_b`를 그대로 읽으면 이번 사이클의
            // 갱신(=idx255 자신이 새 최댓값일 때)이 반영되기 *전* 값을 보게 됨 -- idx255가
            // 우승자인 이벤트에서 renorm을 그릇되게 트리거해 §132 파라미터로는 나올 수 없는
            // 값(2^11배 정도 뻥튀기)이 나왔었음. eff_max_b(이번 사이클 liked까지 합친 값)로
            // 판단해야 오라클(run_bayes_filter_fixed)과 정확히 같아짐.
            if (eff_max_b == {BELIEF_BITS{1'b0}}) begin
              idx <= 8'd0;
              state <= ST_COLLAPSE;
            end else if (eff_max_b < RENORM_LOW) begin
              shift_amt <= 5'd0;
              state <= ST_RENORM_CALC;
            end else begin
              state <= ST_COMMIT;
            end
          end else idx <= idx + 8'd1;
        end

        ST_COLLAPSE: begin
          belief_mem[bank][idx] <= COLLAPSE_VAL;
          if (idx == 8'd255) state <= ST_COMMIT;
          else idx <= idx + 8'd1;
        end

        ST_RENORM_CALC: begin
          if (renorm_step_done) begin
            if (shift_amt == 5'd0) state <= ST_COMMIT;
            else begin idx <= 8'd0; state <= ST_RENORM_APPLY; end
          end else shift_amt <= shift_amt + 5'd1;
        end

        ST_RENORM_APPLY: begin
          belief_mem[bank][idx] <= belief_mem[bank][idx] << shift_amt;
          if (idx == 8'd255) state <= ST_COMMIT;
          else idx <= idx + 8'd1;
        end

        ST_COMMIT: begin
          cnt_on[commit_addr]  <= pol_r ? ((c_on  == CNT_MAX[3:0]) ? c_on  : c_on  + 4'd1) : c_on;
          cnt_off[commit_addr] <= (~pol_r) ? ((c_off == CNT_MAX[3:0]) ? c_off : c_off + 4'd1) : c_off;
          theta_out <= map_theta;
          valid_out <= 1'b1;
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
