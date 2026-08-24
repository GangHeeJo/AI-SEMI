// §98 정리: 최종 제출 RTL에 극성(polarity)을 포함시키기로 확정 -- 그래서 AER->CAV
// transport ledger도 원본(무수정) steal_buf가 아니라 극성판(aer_tx16_..._steal_buf_polarity,
// §95에서 검증된 v1)을 DUT로 다시 만듦. tb_steal_buf_event_logger.v(§93, event-ID FIFO)와
// tb_steal_buf_polarity_uzh_trace.v(§95, polarity 정확성)를 합친 구조.
//
// polarity는 이제 sidecar 전용이 아니라 DUT가 실제로 하드웨어로 실어 보냄(pol_mask0/1) --
// 그래서 이 ledger는 "하드웨어가 실제로 내보낸 극성"(hw_polarity)을 기록하고, join
// 스크립트에서 eventmeta.tsv의 ground-truth 극성과 대조해 진짜 end-to-end 검증을 함.
// event_id/occurrence_timestamp 자체는 여전히 TB에서만 매기고 DUT 입력엔 안 들어감
// (arrival/polarity_in만 DUT 입력, 나머지는 순수 TB shadow).
`timescale 1ns/1ps
module tb_steal_buf_polarity_event_logger;
  reg [1023:0] trace_file_r;
  reg [1023:0] out_file_r;

  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  wire [15:0] overrun_w;
  wire valid0; wire [1:0] row0; wire [3:0] col_mask0; wire [3:0] pol_mask0;
  wire valid1; wire [1:0] row1; wire [3:0] col_mask1; wire [3:0] pol_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity dut(
    .clk(clk), .rst(rst), .arrival(arrival), .polarity_in(polarity_in), .overrun(overrun_w),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .pol_mask0(pol_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .pol_mask1(pol_mask1));

  always #5 clk = ~clk;

  integer fd, out_fd, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer cyc, c, i, drain_until;
  integer generated, delivered, dropped_overrun, phantom_count, error_count, collision_count;
  integer next_event_id;
  reg [15:0] ov_sample;

  reg [1:0]  fifo_depth   [0:15];
  integer    fifo_id0     [0:15];
  integer    fifo_id1     [0:15];
  integer    fifo_arr0    [0:15];
  integer    fifo_arr1    [0:15];
  integer    last_retired_id [0:15];
  reg        was_overrun  [0:15];

  task automatic drain_lane(input integer valid_in, input integer row_in, input [3:0] mask_in, input [3:0] polmask_in, input integer lane_in);
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
              $fdisplay(out_fd, "DELIVERED event_id=%0d source=%0d arrival_cycle=%0d retire_cycle=%0d retire_lane=%0d hw_polarity=%0d latency_cycles=%0d",
                popped_id, idx, popped_arr, cyc, lane_in, polmask_in[c], cyc - popped_arr);
            end
          end
        end
      end
    end
  endtask

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0;
    generated = 0; delivered = 0; dropped_overrun = 0; phantom_count = 0; error_count = 0; collision_count = 0;
    next_event_id = 0;
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
    // addrpol.txt 포맷: cycle addr_mask_hex pol_mask_hex (§94/95/97에서 이미 씀)
    scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);

    @(posedge clk); #1;
    rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0; polarity_in = 16'd0;
      while (have_next && next_cycle == cyc) begin
        for (i = 0; i < 16; i = i + 1) if (next_addr[i]) begin
          generated = generated + 1;
          arrival[i] = 1'b1;
          polarity_in[i] = next_pol[i];
        end
        scan_ret = $fscanf(fd, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      #1;
      ov_sample = overrun_w;
      for (i = 0; i < 16; i = i + 1) begin
        was_overrun[i] = 1'b0;
        if (ov_sample[i]) begin
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

      drain_lane(valid0, row0, col_mask0, pol_mask0, 0);
      drain_lane(valid1, row1, col_mask1, pol_mask1, 1);

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

    arrival = 16'd0; polarity_in = 16'd0;
    drain_until = cyc + 15000;
    for (cyc = cyc; cyc < drain_until; cyc = cyc + 1) begin
      @(posedge clk); #1;
      drain_lane(valid0, row0, col_mask0, pol_mask0, 0);
      drain_lane(valid1, row1, col_mask1, pol_mask1, 1);
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
