// world_mem_writer 레인별 쓰기 후보 버퍼용 최소 동기 FIFO. 범용 IP 아님 -- 이 프로젝트
// 규모(깊이 4, 8개 인스턴스)에 맞춘 최소 구현. push/pop 동시 발생 시 카운트 불변(steal_buf_polarity의
// pending_cnt case문과 같은 패턴).
module small_fifo #(
  parameter integer WIDTH = 13,
  parameter integer DEPTH = 4   // 2의 거듭제곱이어야 함(포인터 wrap 단순화)
)(
  input                  clk,
  input                  rst,
  input                  push,
  input      [WIDTH-1:0] push_data,
  input                  pop,
  output     [WIDTH-1:0] pop_data,
  output                 empty,
  output                 full
);
  localparam integer PTR_BITS = $clog2(DEPTH);

  reg [WIDTH-1:0]    mem [0:DEPTH-1];
  reg [PTR_BITS-1:0] wr_ptr, rd_ptr;
  reg [PTR_BITS:0]   count;

  assign empty    = (count == 0);
  assign full     = (count == DEPTH);
  assign pop_data = mem[rd_ptr];

  always @(posedge clk) begin
    if (rst) begin
      wr_ptr <= {PTR_BITS{1'b0}};
      rd_ptr <= {PTR_BITS{1'b0}};
      count  <= {(PTR_BITS+1){1'b0}};
    end else begin
      if (push && !full) begin
        mem[wr_ptr] <= push_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (pop && !empty) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
      case ({push && !full, pop && !empty})
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end
endmodule
