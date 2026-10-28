`timescale 1ns/1ps
// §139: 1차 TX(aer_tx16_..._cluster2_steal_buf_polarity_pose)를 실 UZH 트레이스로 구동해
// "도착 순서"가 아닌 "arbiter가 실제로 내보낸(delivery) 순서"로 이벤트를 캡처한다.
// pose_mask는 TX가 이벤트 "도착 시점"에 태깅해두므로, delivery 순서로 나열해도 각 이벤트의
// 진짜 발생 시각(theta)은 그대로 보존된다 -- 이 파일 하나로 "arbiter 재정렬이 2차 회전추정
// 정확도를 얼마나 해치는가"를 재현 가능하게 측정하기 위한 (row,col,pol,theta) 시퀀스를 뽑는다.
module tb_arbiter_reorder_capture;
  reg clk = 0;
  reg rst;
  reg [15:0] arrival, polarity_in;
  reg [127:0] theta_idx_in;
  reg [7:0] theta_idx;
  wire [15:0] overrun;
  wire        valid0, valid1;
  wire [1:0]  row0, row1;
  wire [3:0]  col_mask0, col_mask1;
  wire [3:0]  pol_mask0, pol_mask1;
  wire [31:0] pose_mask0, pose_mask1;

  aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose u_tx (
    .clk(clk), .rst(rst),
    .arrival(arrival), .polarity_in(polarity_in), .theta_idx_in(theta_idx_in),
    .stall(1'b0),
    .overrun(overrun),
    .valid0(valid0), .row0(row0), .col_mask0(col_mask0), .pol_mask0(pol_mask0), .pose_mask0(pose_mask0),
    .valid1(valid1), .row1(row1), .col_mask1(col_mask1), .pol_mask1(pol_mask1), .pose_mask1(pose_mask1)
  );

  always #5 clk = ~clk;

  // 소스별(16개) "진짜 도착 사이클" 2-deep 큐 -- RTL의 pending_cnt/pol_fifo0/1와 정확히
  // 같은 push(arrival&&!pending_full)/pop(granted_bitmap) 조건으로 미러링해서, "배출된
  // 이벤트가 실제로는 몇 사이클에 도착했었는지"를 복원한다(8비트 pose_mask는 새 1024단계
  // 스케일에 비해 해상도가 부족해서 안 씀 -- §134/135 리사이즈 이전 스케일에 고정된 값이라
  // 최신 theta 인덱싱과 안 맞음).
  reg [31:0] arr_q0 [0:15];
  reg [31:0] arr_q1 [0:15];
  reg [31:0] deliv_arr0 [0:3];
  reg [31:0] deliv_arr1 [0:3];
  integer sk, dc;

  always @(posedge clk) begin
    if (rst) begin
      for (sk = 0; sk < 16; sk = sk + 1) begin arr_q0[sk] <= 32'd0; arr_q1[sk] <= 32'd0; end
      for (dc = 0; dc < 4; dc = dc + 1) begin deliv_arr0[dc] <= 32'hFFFFFFFF; deliv_arr1[dc] <= 32'hFFFFFFFF; end
    end else begin
      for (dc = 0; dc < 4; dc = dc + 1) begin
        deliv_arr0[dc] <= (u_tx.lane0_valid_c && u_tx.lane0_cols_c[dc]) ? arr_q0[u_tx.lane0_row_c*4 + dc] : 32'hFFFFFFFF;
        deliv_arr1[dc] <= (u_tx.lane1_valid_c && u_tx.lane1_cols_c[dc]) ? arr_q0[u_tx.lane1_row_c*4 + dc] : 32'hFFFFFFFF;
      end
      for (sk = 0; sk < 16; sk = sk + 1) begin
        case ({arrival[sk] && !u_tx.pending_full[sk], u_tx.granted_bitmap[sk]})
          2'b10: if (u_tx.pending_cnt[sk] == 2'd0) arr_q0[sk] <= cyc; else arr_q1[sk] <= cyc;
          2'b01: arr_q0[sk] <= arr_q1[sk];
          2'b11: arr_q0[sk] <= cyc;
          default: ;
        endcase
      end
    end
  end

  integer fd_ev, scan_ret, next_cycle, next_addr, next_pol, have_next;
  integer fd_th, th_cyc, th_val;
  reg [7:0] theta_by_cyc [0:60000];
  integer fd_out;
  integer cyc, i, c, generated, delivered, overrun_total;

  initial begin
    rst = 1; arrival = 16'd0; polarity_in = 16'd0; theta_idx_in = 128'd0;
    generated = 0; delivered = 0; overrun_total = 0;

    fd_th = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.cycle_theta.txt", "r");
    if (fd_th == 0) begin $display("CANNOT_OPEN_CYCLE_THETA"); $finish; end
    while (!$feof(fd_th)) begin
      scan_ret = $fscanf(fd_th, "%d %d", th_cyc, th_val);
      if (scan_ret == 2) theta_by_cyc[th_cyc] = th_val[7:0];
    end
    $fclose(fd_th);

    fd_ev = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt", "r");
    if (fd_ev == 0) begin $display("CANNOT_OPEN_ADDRPOL"); $finish; end
    scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
    have_next = (scan_ret == 3);

    fd_out = $fopen("common_traces_uzh/uzh_shapes_rotation_patch.arbiter_delivered.txt", "w");
    if (fd_out == 0) begin $display("CANNOT_OPEN_OUT"); $finish; end

    @(posedge clk); #1; rst = 0;

    cyc = 0;
    while (have_next) begin
      arrival = 16'd0; polarity_in = 16'd0;
      theta_idx = theta_by_cyc[cyc];
      theta_idx_in = {16{theta_idx}};
      if (have_next && next_cycle == cyc) begin
        arrival = next_addr[15:0];
        polarity_in = next_pol[15:0];
        for (i = 0; i < 16; i = i + 1) if (arrival[i]) generated = generated + 1;
        scan_ret = $fscanf(fd_ev, "%d %h %h", next_cycle, next_addr, next_pol);
        have_next = (scan_ret == 3);
      end
      @(posedge clk); #1;
      for (i = 0; i < 16; i = i + 1) if (u_tx.overrun[i]) overrun_total = overrun_total + 1;
      if (valid0)
        for (c = 0; c < 4; c = c + 1)
          if (col_mask0[c]) begin
            $fwrite(fd_out, "%0d %0d %0d %0d %0d\n", cyc, row0, c, pol_mask0[c], deliv_arr0[c]);
            delivered = delivered + 1;
          end
      if (valid1)
        for (c = 0; c < 4; c = c + 1)
          if (col_mask1[c]) begin
            $fwrite(fd_out, "%0d %0d %0d %0d %0d\n", cyc, row1, c, pol_mask1[c], deliv_arr1[c]);
            delivered = delivered + 1;
          end
      cyc = cyc + 1;
    end
    $fclose(fd_ev);

    arrival = 16'd0; polarity_in = 16'd0;
    for (i = 0; i < 15000; i = i + 1) begin
      theta_idx = (cyc <= 60000) ? theta_by_cyc[cyc] : theta_by_cyc[60000];
      theta_idx_in = {16{theta_idx}};
      @(posedge clk); #1;
      for (c = 0; c < 16; c = c + 1) if (u_tx.overrun[c]) overrun_total = overrun_total + 1;
      if (valid0)
        for (c = 0; c < 4; c = c + 1)
          if (col_mask0[c]) begin
            $fwrite(fd_out, "%0d %0d %0d %0d %0d\n", cyc, row0, c, pol_mask0[c], deliv_arr0[c]);
            delivered = delivered + 1;
          end
      if (valid1)
        for (c = 0; c < 4; c = c + 1)
          if (col_mask1[c]) begin
            $fwrite(fd_out, "%0d %0d %0d %0d %0d\n", cyc, row1, c, pol_mask1[c], deliv_arr1[c]);
            delivered = delivered + 1;
          end
      cyc = cyc + 1;
    end
    $fclose(fd_out);

    // 참고: overrun_total은 steal_buf 도입 전 "1차 경고 비트"라 steal로 구제된 이벤트까지
    // 포함해 과다 집계됨(steal_buf 설계 의도) -- 실손실 여부는 generated==delivered로 판정.
    $display("generated=%0d delivered=%0d overrun_raw_bit=%0d", generated, delivered, overrun_total);
    if (generated == 8503 && delivered == 8503)
      $display("ARBITER_REORDER_CAPTURE_PASS");
    else
      $display("ARBITER_REORDER_CAPTURE_FAIL");
    $finish;
  end
endmodule
