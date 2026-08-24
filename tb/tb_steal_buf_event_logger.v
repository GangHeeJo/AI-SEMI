// tb_steal_buf_trace_phantom_debug.v(검증된 shadow_cnt 2-deep 방식)를 그대로 확장 --
// DUT(aer_tx16_trad_rowcol_fovea_cluster2_steal_buf)는 무수정, event_id/timestamp/
// polarity는 이 TB의 shadow 구조에만 존재하고 DUT 입력에는 절대 연결되지 않음(DUT는
// 여전히 순수 주소만 봄). shadow_cnt를 "카운트만" 대신 "카운트+신원(event_id/도착사이클)"
// 을 갖는 2-deep FIFO로 확장해서, phantom_debug의 기존 체크(phantom/bad_overrun/
// drain-incomplete/conservation) 전부를 그대로 상속하면서 event 단위 delivered/overrun
// 로그(+order-violation 체크)를 추가로 남김.
//
// event_id는 파일로 안 받고 이 TB가 직접 매김: cyclemask.txt를 읽는 순서(cycle 오름차순
// -> source 오름차순, 아래 for(i=0..15) 루프와 동일)로 0부터 순증가시키면, 이게
// scripts/build_uzh_eventmeta.py가 같은 규칙으로 만든 eventmeta.tsv의 event_id와
// 자동으로 일치함(두 산출물이 서로의 ID를 몰라도 정렬됨) -- Verilog에서 64비트
// timestamp를 파싱할 필요가 없어짐.
`timescale 1ns/1ps
module tb_steal_buf_event_logger;
  reg [1023:0] trace_file_r;
  reg [1023:0] out_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf dut(
    .clk(clk), .rst(rst), .arrival(arrival), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1));

  always #5 clk = ~clk;

  integer fd, out_fd, scan_ret, next_cycle, next_mask, have_next;
  integer cyc, c, i, drain_until;
  integer generated, delivered, dropped_overrun, phantom_count, error_count, collision_count;
  integer next_event_id, order_violation_count;

  reg [1:0]  fifo_depth   [0:15];
  integer    fifo_id0     [0:15]; // front(가장 오래된, 다음에 pop될 것)
  integer    fifo_id1     [0:15]; // back(가장 최근 push)
  integer    fifo_arr0    [0:15];
  integer    fifo_arr1    [0:15];
  integer    last_retired_id [0:15];
  reg        was_overrun  [0:15];

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in, input integer lane_in);
    integer idx, popped_id, popped_arr;
    begin
      if (valid_in) begin
        for (c = 0; c < 4; c = c + 1) begin
          if (mask_in[c]) begin
            idx = row_in*4 + c;
            if (fifo_depth[idx] == 2'd0) begin
              phantom_count = phantom_count + 1;
              error_count = error_count + 1;
              $display("PHANTOM cyc=%0d idx=%0d row=%0d col=%0d", cyc, idx, row_in, c);
            end else begin
              popped_id  = fifo_id0[idx];
              popped_arr = fifo_arr0[idx];
              fifo_id0[idx]  = fifo_id1[idx];
              fifo_arr0[idx] = fifo_arr1[idx];
              fifo_depth[idx] = fifo_depth[idx] - 2'd1;
              delivered = delivered + 1;
              if (popped_id <= last_retired_id[idx] && last_retired_id[idx] != -1) begin
                error_count = error_count + 1;
                $display("ORDER_VIOLATION source=%0d popped_id=%0d last_retired_id=%0d",
                  idx, popped_id, last_retired_id[idx]);
              end
              last_retired_id[idx] = popped_id;
              $fdisplay(out_fd, "DELIVERED event_id=%0d source=%0d arrival_cycle=%0d retire_cycle=%0d retire_lane=%0d latency_cycles=%0d",
                popped_id, idx, popped_arr, cyc, lane_in, cyc - popped_arr);
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0; collision_count = 0;
    next_event_id = 0; order_violation_count = 0;
    for (i = 0; i < 16; i = i + 1) begin
      fifo_depth[i] = 2'd0; fifo_id0[i] = -1; fifo_id1[i] = -1;
      fifo_arr0[i] = -1; fifo_arr1[i] = -1; last_retired_id[i] = -1;
    end
    if (!$value$plusargs("TRACE_FILE=%s", trace_file_r)) begin
      $display("MISSING +TRACE_FILE="); $finish;
    end
    if (!$value$plusargs("OUT_FILE=%s", out_file_r)) begin
      $display("MISSING +OUT_FILE="); $finish;
    end
    fd = $fopen(trace_file_r, "r");
    if (fd == 0) begin $display("CANNOT_OPEN_TRACE %0s", trace_file_r); $finish; end
    out_fd = $fopen(out_file_r, "w");
    if (out_fd == 0) begin $display("CANNOT_OPEN_OUT %0s", out_file_r); $finish; end
    scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
    have_next = (scan_ret == 2);

    @(posedge clk); #1;
    rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0;
      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) if (next_mask[i]) begin
          generated = generated + 1;
          arrival[i] = 1'b1;
        end
        scan_ret = $fscanf(fd, "%d %h", next_cycle, next_mask);
        have_next = (scan_ret == 2);
      end
      #1;
      for (i = 0; i < 16; i = i + 1) begin
        was_overrun[i] = 1'b0;
        if (overrun_w[i]) begin
          dropped_overrun = dropped_overrun + 1;
          was_overrun[i] = 1'b1;
          if (fifo_depth[i] != 2'd2) begin
            error_count = error_count + 1;
            $display("BAD_OVERRUN_REPORT src=%0d depth=%0d cyc=%0d", i, fifo_depth[i], cyc);
          end
          $fdisplay(out_fd, "OVERRUN event_id=%0d source=%0d arrival_cycle=%0d",
            next_event_id, i, cyc);
          next_event_id = next_event_id + 1;
        end
      end

      @(posedge clk); #1;

      if (valid0 && valid1 && (row0 == row1)) begin
        collision_count = collision_count + 1;
        error_count = error_count + 1;
        $display("LANE_COLLISION cyc=%0d row=%0d", cyc, row0);
      end

      drain_lane(valid0, row0, col_mask0, 0);
      drain_lane(valid1, row1, col_mask1, 1);

      // arrival[i]가 서고 overrun이 아니었던 소스만 새 event_id를 받아 FIFO에 push됨.
      // event_id는 (cycle asc, source asc) 순서로 매겨져서 eventmeta.tsv와 자동 정렬.
      for (i = 0; i < 16; i = i + 1) begin
        if (arrival[i] && !was_overrun[i]) begin
          if (fifo_depth[i] == 2'd0) begin
            fifo_id0[i] = next_event_id; fifo_arr0[i] = cyc;
          end else begin
            fifo_id1[i] = next_event_id; fifo_arr1[i] = cyc;
          end
          fifo_depth[i] = fifo_depth[i] + 2'd1;
          next_event_id = next_event_id + 1;
        end
      end

      cyc = cyc + 1;
    end

    arrival = 16'd0;
    drain_until = cyc + 15000;
    for (cyc = cyc; cyc < drain_until; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0, 0);
      drain_lane(valid1, row1, col_mask1, 1);
    end

    for (i = 0; i < 16; i = i + 1) begin
      if (fifo_depth[i] != 0) begin
        error_count = error_count + 1;
        $display("DRAIN_INCOMPLETE source=%0d fifo_depth=%0d", i, fifo_depth[i]);
      end
    end
    if ((delivered + dropped_overrun) != generated) begin
      error_count = error_count + 1;
      $display("COUNT_MISMATCH delivered=%0d dropped=%0d sum=%0d generated=%0d",
        delivered, dropped_overrun, delivered+dropped_overrun, generated);
    end
    if (next_event_id != generated) begin
      error_count = error_count + 1;
      $display("EVENT_ID_COUNT_MISMATCH assigned=%0d generated=%0d", next_event_id, generated);
    end

    $display("TRACE=%0s generated=%0d delivered=%0d dropped_overrun=%0d phantom=%0d collisions=%0d",
      trace_file_r, generated, delivered, dropped_overrun, phantom_count, collision_count);
    if (error_count == 0) $display("EVENT_LOGGER_PASS");
    else $display("EVENT_LOGGER_FAIL errors=%0d", error_count);
    $fclose(fd);
    $fclose(out_fd);
    $finish;
  end
endmodule
