// Digital 2차 1단계 통합 -- coord_transform_rmcm 8레인에서 나온 (X,Y,pol) 후보를
// 64x64 world memory에 쓴다. 충돌 정책: 같은 사이클에 같은 칸을 겨냥한 후보가 여럿이면
// "레인 인덱스가 큰 쪽이 이긴다"(Verilog 비블로킹 대입 규칙상 같은 배열 원소에 여러 번
// 쓰면 always 블록 안에서 마지막 문장이 이김 -- 그래서 그냥 순서대로 조건부 대입하면
// 자동으로 이 정책이 됨, 별도 arbiter 불필요). 실측 충돌 빈도가 문제 되면 그때 정책 교체.
module world_mem_writer #(
  parameter integer N_LANES   = 8,
  parameter integer ADDR_BITS = 6
)(
  input                             clk,
  input                             rst,
  input  [N_LANES-1:0]              wr_valid,
  input  [N_LANES*ADDR_BITS-1:0]    wr_x,
  input  [N_LANES*ADDR_BITS-1:0]    wr_y,
  input  [N_LANES-1:0]              wr_pol,
  input                             rd_en,
  input  [ADDR_BITS-1:0]            rd_x,
  input  [ADDR_BITS-1:0]            rd_y,
  output reg                        rd_written,
  output reg                        rd_pol
);
  localparam integer SIDE  = 1 << ADDR_BITS;
  localparam integer DEPTH = SIDE * SIDE;

  reg written [0:DEPTH-1];
  reg cell_pol [0:DEPTH-1];

  integer i;
  wire [ADDR_BITS-1:0] lane_x [0:N_LANES-1];
  wire [ADDR_BITS-1:0] lane_y [0:N_LANES-1];
  genvar g;
  generate
    for (g = 0; g < N_LANES; g = g + 1) begin : LANE_ADDR
      assign lane_x[g] = wr_x[g*ADDR_BITS +: ADDR_BITS];
      assign lane_y[g] = wr_y[g*ADDR_BITS +: ADDR_BITS];
    end
  endgenerate

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < DEPTH; i = i + 1) begin
        written[i]  <= 1'b0;
        cell_pol[i] <= 1'b0;
      end
    end else begin
      for (i = 0; i < N_LANES; i = i + 1) begin
        if (wr_valid[i]) begin
          written[lane_y[i]*SIDE + lane_x[i]]  <= 1'b1;
          cell_pol[lane_y[i]*SIDE + lane_x[i]] <= wr_pol[i];
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      rd_written <= 1'b0;
      rd_pol     <= 1'b0;
    end else if (rd_en) begin
      rd_written <= written[rd_y*SIDE + rd_x];
      rd_pol     <= cell_pol[rd_y*SIDE + rd_x];
    end
  end
endmodule
