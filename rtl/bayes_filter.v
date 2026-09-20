// Digital 2차 2단계 predictor -- scripts/bayes_filter_fixed_model.py:run_bayes_filter_fixed()의
// 고정소수점 오라클(§131/132에서 확정: avg-optimized alpha=2, eps_shift=8)을 RTL로 그대로 재현.
// 이벤트를 하나씩(row,col,pol) 받아 N_THETA개 theta 후보에 대한 belief를 갱신하고, 이번
// 이벤트의 MAP theta를 추정해 내놓는다 -- 그 theta가 aer_tx16_coord_transform_v1(v2)의
// theta_idx 입력으로 흘러들어가 1단계 좌표변환에 쓰인다.
//
// §134(로봇팔 타겟, N_THETA=1024/world map 1024x1024)부터 world memory(칸별 on/off 관측횟수)가
// 1,048,576칸이라 §133까지처럼 내부 플립플롭 배열로 담을 수 없음 -- world_mem_writer.v와 같은
// 관례로 단일 포트 1-cycle latency 동기 SRAM 인터페이스(mem_addr/we/wdata/rdata)를 모듈 밖에
// 노출한다(실제 저장소는 SRAM 매크로/시뮬레이션 메모리 모델). 그 대신 이벤트당 사이클 수가
// 늘어남(§133의 in-place 콤비네이셔널 읽기 1사이클/후보 -> 이번엔 주소발급+데이터수신 2사이클/후보,
// commit도 read+write로 나뉨) -- ponytail: 주소를 한 사이클 앞서 발급하는 파이프라인화로
// 1사이클/후보까지 줄일 수 있지만, predictor는 애초에 이벤트당 수백~수천 사이클 걸리는 전역
// 직렬 필터라 이 정도 배는 구조적 성격을 안 바꾸는 비용 -- PPA 실측 후 필요하면 최적화.
//
// diffuse는 §133과 동일하게 더블버퍼(belief_mem[0]/[1], bank로 스왑)로 이웃의 옛 값을 안전하게
// 읽는다. §133에서 발견한 "idx==마지막 후보에서 collapse/renorm 판단이 그 사이클 자신의 갱신을
// 못 보는" 버그의 교훈(eff_max_b/eff_map_x/eff_map_y로 이번 사이클 갱신까지 합쳐서 판단)을
// 그대로 지킨다.
module bayes_filter #(
  parameter integer N_THETA_BITS = 10,  // §134: 1024단계
  parameter integer COORD_BITS   = 10,  // §134: 1024x1024 world map
  parameter integer EPS_SHIFT    = 8,
  parameter integer BELIEF_BITS  = 32,
  parameter integer LIKE_BITS    = 8,
  parameter integer CNT_MAX      = 15   // 4비트 포화 카운터
)(
  input                          clk,
  input                          rst,
  input                          valid_in,
  input  [1:0]                   row_in,
  input  [1:0]                   col_in,
  input                          pol_in,
  output                         busy,
  output reg                     valid_out,     // 1사이클 펄스: theta_out이 이번 이벤트의 MAP theta
  output reg [N_THETA_BITS-1:0]  theta_out,

  // world memory -- 1-cycle latency 동기 SRAM 단일 포트(실제 저장소는 모듈 밖)
  output [2*COORD_BITS-1:0]      mem_addr,
  output                         mem_we,
  output [7:0]                   mem_wdata,     // {n_on[3:0], n_off[3:0]}
  input  [7:0]                   mem_rdata
);
  `include "rtl/coord_transform_rmcm_lut.vh"
  `include "rtl/bayes_filter_like_lut.vh"

  localparam integer N_THETA = 1 << N_THETA_BITS;

  localparam [BELIEF_BITS-1:0] BELIEF_INIT  = {1'b1, {(BELIEF_BITS-4){1'b0}}}; // 1<<(BITS-4)
  localparam [BELIEF_BITS-1:0] RENORM_LOW   = {1'b1, {16{1'b0}}};              // 1<<16
  localparam [BELIEF_BITS-1:0] COLLAPSE_VAL = BELIEF_INIT >> 8;

  localparam ST_IDLE         = 0,
             ST_DIFFUSE      = 1,
             ST_LIKE_ADDR    = 2,
             ST_LIKE_DATA    = 3,
             ST_COLLAPSE     = 4,
             ST_RENORM_CALC  = 5,
             ST_RENORM_APPLY = 6,
             ST_COMMIT_RD    = 7,
             ST_COMMIT_WR    = 8;
  reg [3:0] state;

  // N_THETA개 theta belief, 더블버퍼(diffuse가 이웃의 옛 값을 읽어야 해서 필요)
  reg [BELIEF_BITS-1:0] belief_mem [0:1][0:N_THETA-1];
  reg                   bank;      // 0/1 -- belief_mem[bank]가 "현재" 값

  reg [1:0] row_r, col_r;
  reg       pol_r;
  reg [N_THETA_BITS-1:0] idx;
  reg [BELIEF_BITS-1:0]  max_b;
  reg [N_THETA_BITS-1:0] map_theta;
  reg [COORD_BITS-1:0]   map_x, map_y;
  reg [4:0] shift_amt;

  reg [2*COORD_BITS-1:0] mem_addr_r;
  reg                    mem_we_r;
  reg [7:0]              mem_wdata_r;
  assign mem_addr  = mem_addr_r;
  assign mem_we    = mem_we_r;
  assign mem_wdata = mem_wdata_r;
  assign busy = (state != ST_IDLE);

  // diffuse 입력(이웃, 현재 bank의 옛 값)
  wire [N_THETA_BITS-1:0] idx_prev = (idx == {N_THETA_BITS{1'b0}}) ? (N_THETA-1) : idx - 1'b1;
  wire [N_THETA_BITS-1:0] idx_next = (idx == N_THETA-1)            ? {N_THETA_BITS{1'b0}} : idx + 1'b1;
  wire [BELIEF_BITS-1:0] b_c = belief_mem[bank][idx];
  wire [BELIEF_BITS-1:0] b_l = belief_mem[bank][idx_prev];
  wire [BELIEF_BITS-1:0] b_r = belief_mem[bank][idx_next];
  wire [BELIEF_BITS-1:0] diffused = b_c - (2 * (b_c >> EPS_SHIFT)) + (b_l >> EPS_SHIFT) + (b_r >> EPS_SHIFT);

  // idx에 대응하는 world 좌표(ST_LIKE_ADDR에서는 "다음에 발급할 주소" 계산에, ST_LIKE_DATA에서는
  // "방금 도착한 데이터가 어느 칸 것인지"(=map_x/y 후보 캐시)에 재사용)
  wire [2*COORD_BITS-1:0] xy = coord_transform_rmcm_lut(row_r, col_r, idx);
  wire [COORD_BITS-1:0]   cx = xy[2*COORD_BITS-1 -: COORD_BITS];
  wire [COORD_BITS-1:0]   cy = xy[COORD_BITS-1 -: COORD_BITS];

  wire [3:0] n_on  = mem_rdata[7:4];
  wire [3:0] n_off = mem_rdata[3:0];
  wire [7:0] like  = bayes_filter_like_lut(n_on, n_off, pol_r);
  wire [BELIEF_BITS+LIKE_BITS-1:0] prod  = belief_mem[bank][idx] * like;
  wire [BELIEF_BITS-1:0]           liked = prod >> LIKE_BITS;

  // §133 교훈: 이번 사이클(idx) 자신의 갱신까지 합친 "진짜" 값으로 판단해야 함 -- 레지스터
  // (max_b/map_x/map_y)를 그대로 읽으면 이번 사이클 갱신 전 값을 보는 논블로킹 자기참조 버그.
  wire [BELIEF_BITS-1:0] eff_max_b = (liked > max_b) ? liked : max_b;
  wire [COORD_BITS-1:0]  eff_map_x = (liked > max_b) ? cx : map_x;
  wire [COORD_BITS-1:0]  eff_map_y = (liked > max_b) ? cy : map_y;

  wire renorm_step_done = ((max_b << (shift_amt + 1)) >= BELIEF_INIT) || (shift_amt == 5'd31);

  wire [3:0] c_on  = mem_rdata[7:4];
  wire [3:0] c_off = mem_rdata[3:0];

  integer bi;
  always @(posedge clk) begin
    if (rst) begin
      state <= ST_IDLE;
      bank <= 1'b0;
      valid_out <= 1'b0;
      theta_out <= {N_THETA_BITS{1'b0}};
      max_b <= {BELIEF_BITS{1'b0}};
      map_theta <= {N_THETA_BITS{1'b0}};
      map_x <= {COORD_BITS{1'b0}}; map_y <= {COORD_BITS{1'b0}};
      mem_addr_r <= {2*COORD_BITS{1'b0}};
      mem_we_r <= 1'b0;
      mem_wdata_r <= 8'd0;
      for (bi = 0; bi < N_THETA; bi = bi + 1)
        belief_mem[0][bi] <= (bi == 0) ? BELIEF_INIT : {BELIEF_BITS{1'b0}};
    end else begin
      valid_out <= 1'b0;
      mem_we_r <= 1'b0;  // 기본은 읽기/유휴 -- ST_COMMIT_WR에서만 1로 켬
      case (state)
        ST_IDLE: begin
          if (valid_in) begin
            row_r <= row_in; col_r <= col_in; pol_r <= pol_in;
            idx <= {N_THETA_BITS{1'b0}};
            state <= ST_DIFFUSE;
          end
        end

        ST_DIFFUSE: begin
          belief_mem[~bank][idx] <= diffused;
          if (idx == N_THETA-1) begin
            bank <= ~bank;
            idx <= {N_THETA_BITS{1'b0}};
            max_b <= {BELIEF_BITS{1'b0}};
            map_theta <= {N_THETA_BITS{1'b0}};
            map_x <= {COORD_BITS{1'b0}}; map_y <= {COORD_BITS{1'b0}};
            // theta=0 후보 주소를 미리 발급(다음 상태에서 SRAM이 이 주소를 래치)
            mem_addr_r <= coord_transform_rmcm_lut(row_r, col_r, {N_THETA_BITS{1'b0}});
            state <= ST_LIKE_ADDR;
          end else idx <= idx + 1'b1;
        end

        ST_LIKE_ADDR: begin
          // mem_addr_r은 이전 사이클에 이미 실어둠 -- 이번 사이클 동안 안정적으로 유지되고
          // 있어야 (모델링한) SRAM이 다음 사이클에 데이터를 내놓음.
          state <= ST_LIKE_DATA;
        end

        ST_LIKE_DATA: begin
          // mem_rdata는 지금 idx 후보의 값(1사이클 전 ST_LIKE_ADDR에서 발급한 주소 응답)
          belief_mem[bank][idx] <= liked;
          if (liked > max_b) begin
            max_b <= liked;
            map_theta <= idx;
            map_x <= cx; map_y <= cy;
          end
          if (idx == N_THETA-1) begin
            // python처럼 두 검사(collapse, renorm)를 순서대로: collapse면 renorm 조건이
            // 자동으로 거짓이 되는 파라미터 관계(COLLAPSE_VAL=2^20 > RENORM_LOW=2^16)라
            // collapse 후 renorm 재검사는 생략(§132 실측 확인).
            if (eff_max_b == {BELIEF_BITS{1'b0}}) begin
              idx <= {N_THETA_BITS{1'b0}};
              state <= ST_COLLAPSE;
            end else if (eff_max_b < RENORM_LOW) begin
              shift_amt <= 5'd0;
              state <= ST_RENORM_CALC;
            end else begin
              mem_addr_r <= {eff_map_x, eff_map_y};
              state <= ST_COMMIT_RD;
            end
          end else begin
            idx <= idx + 1'b1;
            mem_addr_r <= coord_transform_rmcm_lut(row_r, col_r, idx + 1'b1);
            state <= ST_LIKE_ADDR;
          end
        end

        ST_COLLAPSE: begin
          belief_mem[bank][idx] <= COLLAPSE_VAL;
          if (idx == N_THETA-1) begin
            mem_addr_r <= {map_x, map_y};
            state <= ST_COMMIT_RD;
          end else idx <= idx + 1'b1;
        end

        ST_RENORM_CALC: begin
          if (renorm_step_done) begin
            if (shift_amt == 5'd0) begin
              mem_addr_r <= {map_x, map_y};
              state <= ST_COMMIT_RD;
            end else begin idx <= {N_THETA_BITS{1'b0}}; state <= ST_RENORM_APPLY; end
          end else shift_amt <= shift_amt + 5'd1;
        end

        ST_RENORM_APPLY: begin
          belief_mem[bank][idx] <= belief_mem[bank][idx] << shift_amt;
          if (idx == N_THETA-1) begin
            mem_addr_r <= {map_x, map_y};
            state <= ST_COMMIT_RD;
          end else idx <= idx + 1'b1;
        end

        ST_COMMIT_RD: begin
          // mem_addr_r은 ST_LIKE_DATA/COLLAPSE/RENORM_APPLY/RENORM_CALC 끝에서 이미 실어둠 --
          // 이번 사이클 동안 안정 유지, 다음 사이클에 mem_rdata로 현재 카운트가 도착.
          state <= ST_COMMIT_WR;
        end

        ST_COMMIT_WR: begin
          mem_we_r <= 1'b1;
          mem_wdata_r <= { pol_r  ? ((c_on  == CNT_MAX[3:0]) ? c_on  : c_on  + 4'd1) : c_on,
                            (~pol_r) ? ((c_off == CNT_MAX[3:0]) ? c_off : c_off + 4'd1) : c_off };
          theta_out <= map_theta;
          valid_out <= 1'b1;
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
