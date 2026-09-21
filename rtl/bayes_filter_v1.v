// §134/135에서 rtl/bayes_filter.v(범용 모듈)와 그 world memory를 predictor 신규 타겟 크기
// (1024단계/1024x1024, 외부 SRAM 포트)로 키우면서, aer_tx16_coord_transform_v2.v(predictor+
// 1단계 통합, §134)가 계속 컴파일/동작하도록 옛 크기(256단계/64x64, 내부 FF world_mem) 스냅샷을
// 별도 파일로 얼려둔 것 -- coord_transform_rmcm_v1.v와 같은 패턴. 내용은 §133 커밋 시점과
// 완전히 동일(§133에서 잡은 eff_max_b 자기참조 버그 수정 포함), 모듈명/LUT include만 `_v1`
// 접미사로 충돌 회피. 1단계 자체를 새 크기로 다시 검증하며 키울 때 이 파일은 지우고 v2가
// bayes_filter(신판)를 쓰도록 되돌리면 됨.
module bayes_filter_v1 #(
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
  `include "rtl/coord_transform_rmcm_lut_v1.vh"
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
  wire [11:0] xy   = coord_transform_rmcm_lut_v1(row_r, col_r, idx);
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
