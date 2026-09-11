`timescale 1ns/1ps
module tb_affine_region_coeff_table2;
  localparam integer REGION_COLS = 2;
  localparam integer REGION_ROWS = 2;
  localparam integer REGION_X_W = 1;
  localparam integer REGION_Y_W = 1;
  localparam integer REGION_ID_W = 2;
  localparam integer POSE_W = 1;
  localparam integer MATRIX_W = 16;
  localparam integer OFFSET_W = 24;
  localparam integer REGION_COUNT = REGION_COLS * REGION_ROWS;

  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;

  reg clk = 1'b0;
  reg rst;

  reg cfg_valid;
  wire cfg_ready;
  reg [1:0] cfg_op;
  reg [REGION_X_W-1:0] cfg_region_x;
  reg [REGION_Y_W-1:0] cfg_region_y;
  reg [POSE_W-1:0] cfg_pose_version;
  reg signed [MATRIX_W-1:0] cfg_m00;
  reg signed [MATRIX_W-1:0] cfg_m01;
  reg signed [MATRIX_W-1:0] cfg_m10;
  reg signed [MATRIX_W-1:0] cfg_m11;
  reg signed [OFFSET_W-1:0] cfg_tx;
  reg signed [OFFSET_W-1:0] cfg_ty;

  wire region_wr_req;
  wire [REGION_X_W-1:0] region_wr_x;
  wire [REGION_Y_W-1:0] region_wr_y;
  wire [POSE_W-1:0] region_wr_pose_version;
  wire signed [MATRIX_W-1:0] region_wr_m00;
  wire signed [MATRIX_W-1:0] region_wr_m01;
  wire signed [MATRIX_W-1:0] region_wr_m10;
  wire signed [MATRIX_W-1:0] region_wr_m11;
  wire signed [OFFSET_W-1:0] region_wr_tx;
  wire signed [OFFSET_W-1:0] region_wr_ty;
  wire region_wr_ready;
  wire region_wr_commit;
  reg [1:0] pose_overwrite_ready;

  wire active_pose_valid;
  wire [POSE_W-1:0] active_pose_version;
  wire load_busy;
  wire awaiting_publish;
  wire publish_pulse;
  wire cfg_protocol_error;

  reg lookup_valid;
  wire lookup_ready;
  reg [POSE_W-1:0] lookup_pose_version;
  reg [REGION_ID_W-1:0] lookup_region_id;
  wire lookup_rsp_valid;
  reg lookup_rsp_ready;
  wire lookup_rsp_found;
  wire signed [MATRIX_W-1:0] lookup_rsp_m00;
  wire signed [MATRIX_W-1:0] lookup_rsp_m01;
  wire signed [MATRIX_W-1:0] lookup_rsp_m10;
  wire signed [MATRIX_W-1:0] lookup_rsp_m11;
  wire signed [OFFSET_W-1:0] lookup_rsp_tx;
  wire signed [OFFSET_W-1:0] lookup_rsp_ty;

  integer errors;
  integer write_commits;
  integer publish_count;
  integer commits_before_stall;
  integer region_index;
  integer x;
  integer y;
  reg stalled_found;
  reg signed [MATRIX_W-1:0] stalled_m00;
  reg signed [MATRIX_W-1:0] stalled_m01;
  reg signed [MATRIX_W-1:0] stalled_m10;
  reg signed [MATRIX_W-1:0] stalled_m11;
  reg signed [OFFSET_W-1:0] stalled_tx;
  reg signed [OFFSET_W-1:0] stalled_ty;

  affine_region_pose_loader #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(REGION_X_W), .REGION_Y_W(REGION_Y_W),
    .POSE_W(POSE_W), .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) loader (
    .clk(clk), .rst(rst),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_op(cfg_op),
    .cfg_region_x(cfg_region_x), .cfg_region_y(cfg_region_y),
    .cfg_pose_version(cfg_pose_version),
    .cfg_m00(cfg_m00), .cfg_m01(cfg_m01),
    .cfg_m10(cfg_m10), .cfg_m11(cfg_m11),
    .cfg_tx(cfg_tx), .cfg_ty(cfg_ty),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .region_pose_accounting_error(1'b0),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .load_busy(load_busy), .awaiting_publish(awaiting_publish),
    .expected_region_x(), .expected_region_y(),
    .load_pose_version(), .publish_pulse(publish_pulse),
    .cfg_protocol_error(cfg_protocol_error)
  );

  affine_region_coeff_table2 #(
    .REGION_COLS(REGION_COLS), .REGION_ROWS(REGION_ROWS),
    .REGION_X_W(REGION_X_W), .REGION_Y_W(REGION_Y_W),
    .REGION_ID_W(REGION_ID_W), .POSE_W(POSE_W),
    .MATRIX_W(MATRIX_W), .OFFSET_W(OFFSET_W)
  ) coeff_table (
    .clk(clk), .rst(rst),
    .region_wr_req(region_wr_req),
    .region_wr_x(region_wr_x), .region_wr_y(region_wr_y),
    .region_wr_pose_version(region_wr_pose_version),
    .region_wr_m00(region_wr_m00), .region_wr_m01(region_wr_m01),
    .region_wr_m10(region_wr_m10), .region_wr_m11(region_wr_m11),
    .region_wr_tx(region_wr_tx), .region_wr_ty(region_wr_ty),
    .region_wr_ready(region_wr_ready),
    .region_wr_commit(region_wr_commit),
    .pose_overwrite_ready(pose_overwrite_ready),
    .publish_pulse(publish_pulse),
    .publish_pose_version(active_pose_version),
    .lookup_valid(lookup_valid), .lookup_ready(lookup_ready),
    .lookup_pose_version(lookup_pose_version),
    .lookup_region_id(lookup_region_id),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_found(lookup_rsp_found),
    .lookup_rsp_m00(lookup_rsp_m00), .lookup_rsp_m01(lookup_rsp_m01),
    .lookup_rsp_m10(lookup_rsp_m10), .lookup_rsp_m11(lookup_rsp_m11),
    .lookup_rsp_tx(lookup_rsp_tx), .lookup_rsp_ty(lookup_rsp_ty)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (!rst && region_wr_commit)
      write_commits = write_commits + 1;
    if (!rst && publish_pulse)
      publish_count = publish_count + 1;
  end

  task automatic check_condition;
    input condition;
    input [8*96-1:0] message;
    begin
      if (condition !== 1'b1) begin
        errors = errors + 1;
        $display("CHECK_FAIL %0s", message);
      end
    end
  endtask

  task automatic drive_cfg;
    input [1:0] op_in;
    input integer x_in;
    input integer y_in;
    input [POSE_W-1:0] pose_in;
    input integer seed;
    begin
      cfg_op = op_in;
      cfg_region_x = x_in;
      cfg_region_y = y_in;
      cfg_pose_version = pose_in;
      cfg_m00 = seed;
      cfg_m01 = -seed-1;
      cfg_m10 = seed+2;
      cfg_m11 = -seed-3;
      cfg_tx = seed*17;
      cfg_ty = -seed*19;
      cfg_valid = 1'b1;
    end
  endtask

  task automatic finish_cfg_handshake;
    begin
      #1;
      while (cfg_ready !== 1'b1)
        @(negedge clk);
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task automatic send_begin;
    input [POSE_W-1:0] pose_in;
    begin
      @(negedge clk);
      drive_cfg(CFG_BEGIN, 0, 0, pose_in, 0);
      finish_cfg_handshake;
    end
  endtask

  task automatic send_write;
    input integer x_in;
    input integer y_in;
    input [POSE_W-1:0] pose_in;
    input integer seed;
    begin
      @(negedge clk);
      drive_cfg(CFG_WRITE, x_in, y_in, pose_in, seed);
      finish_cfg_handshake;
    end
  endtask

  task automatic send_publish;
    input [POSE_W-1:0] pose_in;
    begin
      @(negedge clk);
      drive_cfg(CFG_PUBLISH, 0, 0, pose_in, 0);
      finish_cfg_handshake;
      check_condition(publish_pulse && active_pose_valid &&
                      active_pose_version == pose_in,
                      "loader published requested pose");
    end
  endtask

  task automatic lookup_expect;
    input [POSE_W-1:0] pose_in;
    input integer region_in;
    input expected_found;
    input integer seed;
    begin
      @(negedge clk);
      lookup_pose_version = pose_in;
      lookup_region_id = region_in;
      lookup_valid = 1'b1;
      lookup_rsp_ready = 1'b1;
      #1;
      check_condition(lookup_ready, "lookup request accepted");
      @(posedge clk);
      #1;
      lookup_valid = 1'b0;
      check_condition(lookup_rsp_valid, "synchronous lookup response valid");
      check_condition(lookup_rsp_found == expected_found,
                      "lookup found value");
      if (expected_found) begin
        check_condition(
          lookup_rsp_m00 == seed && lookup_rsp_m01 == -seed-1 &&
          lookup_rsp_m10 == seed+2 && lookup_rsp_m11 == -seed-3 &&
          lookup_rsp_tx == seed*17 && lookup_rsp_ty == -seed*19,
          "lookup coefficient payload"
        );
      end else begin
        check_condition(
          lookup_rsp_m00 == 0 && lookup_rsp_m01 == 0 &&
          lookup_rsp_m10 == 0 && lookup_rsp_m11 == 0 &&
          lookup_rsp_tx == 0 && lookup_rsp_ty == 0,
          "not-found response payload is zero"
        );
      end
    end
  endtask

  task automatic load_remaining;
    input [POSE_W-1:0] pose_in;
    input integer seed_base;
    begin
      send_write(1, 0, pose_in, seed_base+1);
      send_write(0, 1, pose_in, seed_base+2);
      send_write(1, 1, pose_in, seed_base+3);
      check_condition(awaiting_publish, "four row-major writes complete");
    end
  endtask

  task automatic check_epoch;
    input [POSE_W-1:0] pose_in;
    input integer seed_base;
    begin
      for (region_index = 0; region_index < REGION_COUNT;
           region_index = region_index + 1)
        lookup_expect(pose_in, region_index, 1'b1,
                      seed_base+region_index);
    end
  endtask

  initial begin
    errors = 0;
    write_commits = 0;
    publish_count = 0;
    rst = 1'b1;
    cfg_valid = 1'b0;
    cfg_op = CFG_BEGIN;
    cfg_region_x = 0;
    cfg_region_y = 0;
    cfg_pose_version = 0;
    cfg_m00 = 0;
    cfg_m01 = 0;
    cfg_m10 = 0;
    cfg_m11 = 0;
    cfg_tx = 0;
    cfg_ty = 0;
    pose_overwrite_ready = 2'b11;
    lookup_valid = 1'b0;
    lookup_pose_version = 0;
    lookup_region_id = 0;
    lookup_rsp_ready = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Reset records and an incomplete first generation are invisible.
    lookup_expect(1'b0, 0, 1'b0, 0);
    send_begin(1'b0);
    send_write(0, 0, 1'b0, 100);
    lookup_expect(1'b0, 0, 1'b0, 0);
    load_remaining(1'b0, 100);
    lookup_expect(1'b0, 3, 1'b0, 0);
    send_publish(1'b0);
    check_epoch(1'b0, 100);

    // Loading pose 1 leaves the complete old pose 0 bank readable.
    send_begin(1'b1);
    send_write(0, 0, 1'b1, 200);
    lookup_expect(1'b1, 0, 1'b0, 0);
    lookup_expect(1'b0, 3, 1'b1, 103);
    load_remaining(1'b1, 200);
    send_publish(1'b1);
    check_epoch(1'b1, 200);
    check_epoch(1'b0, 100);

    // One outstanding response applies backpressure and remains bit-stable.
    @(posedge clk);
    #1;
    check_condition(!lookup_rsp_valid, "previous lookup response consumed");
    @(negedge clk);
    lookup_rsp_ready = 1'b0;
    lookup_pose_version = 1'b0;
    lookup_region_id = 2;
    lookup_valid = 1'b1;
    #1;
    check_condition(lookup_ready, "initial stalled lookup accepted");
    @(posedge clk);
    #1;
    lookup_pose_version = 1'b1;
    lookup_region_id = 1;
    stalled_found = lookup_rsp_found;
    stalled_m00 = lookup_rsp_m00;
    stalled_m01 = lookup_rsp_m01;
    stalled_m10 = lookup_rsp_m10;
    stalled_m11 = lookup_rsp_m11;
    stalled_tx = lookup_rsp_tx;
    stalled_ty = lookup_rsp_ty;
    check_condition(stalled_found && stalled_m00 == 102,
                    "stalled response captured requested record");
    repeat (3) begin
      @(posedge clk);
      #1;
      check_condition(lookup_rsp_valid && !lookup_ready,
                      "outstanding response backpressures lookup");
      check_condition(
        lookup_rsp_found == stalled_found &&
        lookup_rsp_m00 == stalled_m00 && lookup_rsp_m01 == stalled_m01 &&
        lookup_rsp_m10 == stalled_m10 && lookup_rsp_m11 == stalled_m11 &&
        lookup_rsp_tx == stalled_tx && lookup_rsp_ty == stalled_ty,
        "stalled response payload stable"
      );
    end
    @(negedge clk);
    lookup_rsp_ready = 1'b1;
    #1;
    check_condition(lookup_ready, "response release accepts held request");
    @(posedge clk);
    #1;
    lookup_valid = 1'b0;
    check_condition(lookup_rsp_valid && lookup_rsp_found &&
                    lookup_rsp_m00 == 201,
                    "held lookup completed after response release");

    // Pose 0 remains readable after pose 1 publication until its own rewrite.
    lookup_expect(1'b0, 1, 1'b1, 101);
    send_begin(1'b0);
    @(negedge clk);
    pose_overwrite_ready[0] = 1'b0;
    drive_cfg(CFG_WRITE, 0, 0, 1'b0, 300);
    commits_before_stall = write_commits;
    repeat (2) begin
      @(posedge clk);
      #1;
      check_condition(!cfg_ready && !region_wr_req && !region_wr_commit,
                      "busy old epoch blocks table write");
      check_condition(write_commits == commits_before_stall,
                      "blocked old epoch made no commit");
    end

    // The preceding edge models last-retire.  Ready rises afterward, so the
    // write commits only on the next edge.  A same-bank lookup on that edge
    // deterministically returns not-found rather than stale or partial data.
    @(negedge clk);
    pose_overwrite_ready[0] = 1'b1;
    lookup_pose_version = 1'b0;
    lookup_region_id = 1;
    lookup_valid = 1'b1;
    lookup_rsp_ready = 1'b1;
    #1;
    check_condition(cfg_ready && region_wr_req && region_wr_commit,
                    "old epoch becomes writable after last-retire cycle");
    check_condition(lookup_ready, "same-bank safety lookup accepted");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    lookup_valid = 1'b0;
    check_condition(write_commits == commits_before_stall+1,
                    "released old epoch committed exactly once");
    check_condition(lookup_rsp_valid && !lookup_rsp_found,
                    "same-cycle rewrite hides complete target bank");
    lookup_expect(1'b0, 3, 1'b0, 0);
    lookup_expect(1'b1, 3, 1'b1, 203);

    load_remaining(1'b0, 300);
    lookup_expect(1'b0, 2, 1'b0, 0);
    send_publish(1'b0);
    check_epoch(1'b0, 300);
    check_epoch(1'b1, 200);

    check_condition(write_commits == 3*REGION_COUNT,
                    "three epochs wrote exactly four records each");
    check_condition(publish_count == 3,
                    "three complete epochs published");
    check_condition(!cfg_protocol_error && !load_busy,
                    "loader/table protocol stayed healthy");

    if (errors == 0) begin
      $display("AFFINE_REGION_COEFF_TABLE2_PASS regions=%0d commits=%0d",
               REGION_COUNT, write_commits);
      $finish;
    end else begin
      $fatal(1, "AFFINE_REGION_COEFF_TABLE2_FAIL errors=%0d", errors);
    end
  end

  initial begin
    #500000;
    $fatal(1, "AFFINE_REGION_COEFF_TABLE2_TIMEOUT");
  end
endmodule
