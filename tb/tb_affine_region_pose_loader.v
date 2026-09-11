`timescale 1ns/1ps
module tb_affine_region_pose_loader;
  parameter REGION_COLS = 3;
  parameter REGION_ROWS = 2;
  localparam REGION_X_W = (REGION_COLS < 2) ? 1 : $clog2(REGION_COLS);
  localparam REGION_Y_W = (REGION_ROWS < 2) ? 1 : $clog2(REGION_ROWS);
  localparam POSE_W = 1;
  localparam MATRIX_W = 16;
  localparam OFFSET_W = 24;
  localparam REGION_COUNT = REGION_COLS * REGION_ROWS;
  localparam REGION_INDEX_W =
    (REGION_COUNT < 2) ? 1 : $clog2(REGION_COUNT);

  localparam [1:0] CFG_BEGIN = 2'd0;
  localparam [1:0] CFG_WRITE = 2'd1;
  localparam [1:0] CFG_PUBLISH = 2'd2;
  localparam [1:0] CFG_ABORT = 2'd3;

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
  reg [REGION_COUNT-1:0] region_ready_map;
  wire [REGION_INDEX_W-1:0] selected_region_index =
    region_wr_y * REGION_COLS + region_wr_x;
  wire region_wr_ready = region_ready_map[selected_region_index];
  reg suppress_region_commit;
  reg force_spurious_commit;
  wire region_wr_commit = force_spurious_commit ||
    (region_wr_req && region_wr_ready && !suppress_region_commit);
  reg region_pose_accounting_error;

  wire active_pose_valid;
  wire [POSE_W-1:0] active_pose_version;
  wire load_busy;
  wire awaiting_publish;
  wire [REGION_X_W-1:0] expected_region_x;
  wire [REGION_Y_W-1:0] expected_region_y;
  wire [POSE_W-1:0] load_pose_version;
  wire publish_pulse;
  wire cfg_protocol_error;

  integer errors;
  integer write_commits;
  integer publish_count;
  integer commits_before_fault;
  integer x;
  integer y;
  reg capture_event;
  reg [POSE_W-1:0] captured_event_pose;
  reg signed [MATRIX_W-1:0] shadow_m00 [0:2*REGION_COUNT-1];
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
  ) dut (
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
    .region_pose_accounting_error(region_pose_accounting_error),
    .active_pose_valid(active_pose_valid),
    .active_pose_version(active_pose_version),
    .load_busy(load_busy), .awaiting_publish(awaiting_publish),
    .expected_region_x(expected_region_x),
    .expected_region_y(expected_region_y),
    .load_pose_version(load_pose_version),
    .publish_pulse(publish_pulse),
    .cfg_protocol_error(cfg_protocol_error)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst) begin
      captured_event_pose <= {POSE_W{1'b0}};
    end else if (capture_event) begin
      captured_event_pose <= active_pose_version;
    end
    if (!rst && region_wr_req && region_wr_commit) begin
      write_commits = write_commits + 1;
      shadow_m00[region_wr_pose_version*REGION_COUNT+
                 selected_region_index] = region_wr_m00;
    end
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

  task automatic reset_dut;
    begin
      @(negedge clk);
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
      region_ready_map = {REGION_COUNT{1'b1}};
      suppress_region_commit = 1'b0;
      force_spurious_commit = 1'b0;
      region_pose_accounting_error = 1'b0;
      capture_event = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      check_condition(!active_pose_valid && !load_busy && !awaiting_publish,
             "reset state");
      check_condition(!cfg_protocol_error && !region_wr_req && !publish_pulse,
             "reset outputs");
      @(negedge clk);
      rst = 1'b0;
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
      #1;
      while (cfg_ready !== 1'b1)
        @(negedge clk);
      #1;
      check_condition(region_wr_req, "expected region request");
      check_condition(region_wr_x == x_in && region_wr_y == y_in,
             "region address forwarding");
      check_condition(region_wr_pose_version == pose_in,
             "pose forwarding");
      check_condition(region_wr_m00 == seed && region_wr_m01 == -seed-1 &&
             region_wr_m10 == seed+2 && region_wr_m11 == -seed-3 &&
             region_wr_tx == seed*17 && region_wr_ty == -seed*19,
             "coefficient forwarding");
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
    end
  endtask

  task automatic send_abort;
    input [POSE_W-1:0] pose_in;
    begin
      @(negedge clk);
      drive_cfg(CFG_ABORT, 0, 0, pose_in, 0);
      finish_cfg_handshake;
    end
  endtask

  task automatic check_published_m00;
    input [POSE_W-1:0] pose_in;
    input integer seed_base;
    integer region_index;
    begin
      for (region_index = 0;
           region_index < REGION_COUNT;
           region_index = region_index + 1)
        check_condition(
          shadow_m00[pose_in*REGION_COUNT+region_index] ==
          seed_base+region_index,
          "published epoch contains one complete coefficient generation"
        );
    end
  endtask

  task automatic send_publish_with_edge_capture;
    input [POSE_W-1:0] pose_in;
    input [POSE_W-1:0] old_pose;
    begin
      @(negedge clk);
      drive_cfg(CFG_PUBLISH, 0, 0, pose_in, 0);
      capture_event = 1'b1;
      @(posedge clk);
      #1;
      cfg_valid = 1'b0;
      capture_event = 1'b0;
      check_condition(publish_pulse, "publish pulse");
      check_condition(active_pose_valid && active_pose_version == pose_in,
             "published active pose");
      check_condition(captured_event_pose == old_pose,
             "publish-edge event kept old pose");
      @(posedge clk);
      #1;
      check_condition(!publish_pulse, "publish pulse width");
      @(negedge clk);
      capture_event = 1'b1;
      @(posedge clk);
      #1;
      capture_event = 1'b0;
      check_condition(captured_event_pose == pose_in,
             "next-cycle event saw new pose");
    end
  endtask

  task automatic load_all_regions;
    input [POSE_W-1:0] pose_in;
    input integer seed_base;
    begin
      send_begin(pose_in);
      #1;
      check_condition(load_busy && load_pose_version == pose_in,
             "begin entered load state");
      for (y = 0; y < REGION_ROWS; y = y + 1)
        for (x = 0; x < REGION_COLS; x = x + 1)
          send_write(x, y, pose_in, seed_base + y*REGION_COLS + x);
      #1;
      check_condition(awaiting_publish && load_busy,
             "all writes wait for explicit publish");
    end
  endtask

  initial begin
    errors = 0;
    write_commits = 0;
    publish_count = 0;
    rst = 1'b1;
    cfg_valid = 1'b0;
    cfg_op = 0;
    cfg_region_x = 0;
    cfg_region_y = 0;
    cfg_pose_version = 0;
    cfg_m00 = 0;
    cfg_m01 = 0;
    cfg_m10 = 0;
    cfg_m11 = 0;
    cfg_tx = 0;
    cfg_ty = 0;
    region_ready_map = {REGION_COUNT{1'b1}};
    suppress_region_commit = 1'b0;
    force_spurious_commit = 1'b0;
    region_pose_accounting_error = 1'b0;
    capture_event = 1'b0;

    // Two complete epochs prove ordered distribution and atomic publication.
    reset_dut;
    send_begin(1'b1);
    @(negedge clk);
    region_ready_map[0] = 1'b0;
    drive_cfg(CFG_WRITE, 0, 0, 1'b1, 100);
    #1;
    stalled_m00 = region_wr_m00;
    stalled_m01 = region_wr_m01;
    stalled_m10 = region_wr_m10;
    stalled_m11 = region_wr_m11;
    stalled_tx = region_wr_tx;
    stalled_ty = region_wr_ty;
    repeat (3) begin
      @(posedge clk);
      #1;
      check_condition(!region_wr_req && !cfg_ready && !region_wr_commit,
                      "busy region backpressured write");
      check_condition(!active_pose_valid && expected_region_x == 0 &&
                      expected_region_y == 0,
                      "stalled write stayed atomic/stable");
      check_condition(
        region_wr_x == 0 && region_wr_y == 0 &&
        region_wr_pose_version == 1'b1 &&
        region_wr_m00 == stalled_m00 && region_wr_m01 == stalled_m01 &&
        region_wr_m10 == stalled_m10 && region_wr_m11 == stalled_m11 &&
        region_wr_tx == stalled_tx && region_wr_ty == stalled_ty,
        "stalled region payload stayed stable"
      );
    end
    @(negedge clk);
    region_ready_map[0] = 1'b1;
    finish_cfg_handshake;
    if (REGION_COUNT > 2)
      region_ready_map[REGION_COUNT-1] = 1'b0;
    for (x = 1; x < REGION_COLS; x = x + 1)
      send_write(x, 0, 1'b1, 100+x);
    if (REGION_COUNT > 2)
      region_ready_map[REGION_COUNT-1] = 1'b1;
    for (y = 1; y < REGION_ROWS; y = y + 1)
      for (x = 0; x < REGION_COLS; x = x + 1)
        send_write(x, y, 1'b1, 100+y*REGION_COLS+x);
    check_condition(awaiting_publish && !active_pose_valid,
                    "no early first publication");
    send_publish_with_edge_capture(1'b1, 1'b0);
    check_published_m00(1'b1, 100);

    load_all_regions(1'b0, 200);
    check_condition(active_pose_version == 1'b1,
                    "old epoch remains active during second load");
    send_publish_with_edge_capture(1'b0, 1'b1);
    check_published_m00(1'b0, 200);
    check_condition(write_commits == 2*REGION_COUNT,
                    "exact write count for two epochs");
    check_condition(publish_count == 2,
                    "exact publish count for two epochs");

    // Reusing the old slot stalls only on the selected busy region.  The
    // third stalled edge models last-retire; ready rises on the next cycle.
    send_begin(1'b1);
    send_write(0, 0, 1'b1, 300);
    @(negedge clk);
    region_ready_map[1] = 1'b0;
    drive_cfg(CFG_WRITE, 1, 0, 1'b1, 301);
    #1;
    commits_before_fault = write_commits;
    repeat (3) begin
      @(posedge clk);
      #1;
      check_condition(!region_wr_req && !cfg_ready,
                      "old-slot selected region remained busy");
      check_condition(write_commits == commits_before_fault,
                      "old-slot stall made no duplicate commit");
    end
    @(negedge clk);
    region_ready_map[1] = 1'b1;
    finish_cfg_handshake;
    check_condition(write_commits == commits_before_fault+1,
                    "old-slot region committed exactly once");
    for (x = 2; x < REGION_COLS; x = x + 1)
      send_write(x, 0, 1'b1, 300+x);
    for (y = 1; y < REGION_ROWS; y = y + 1)
      for (x = 0; x < REGION_COLS; x = x + 1)
        if (x != REGION_COLS-1 || y != REGION_ROWS-1)
          send_write(x, y, 1'b1, 300+y*REGION_COLS+x);
    @(negedge clk);
    region_ready_map[REGION_COUNT-1] = 1'b0;
    drive_cfg(CFG_WRITE, REGION_COLS-1, REGION_ROWS-1, 1'b1,
              300+REGION_COUNT-1);
    repeat (2) begin
      @(posedge clk);
      #1;
      check_condition(!region_wr_req && !region_wr_commit &&
                      !awaiting_publish,
                      "final-region stall blocked early publication");
      check_condition(expected_region_x == REGION_COLS-1 &&
                      expected_region_y == REGION_ROWS-1,
                      "final-region stall held raster endpoint");
    end
    @(negedge clk);
    region_ready_map[REGION_COUNT-1] = 1'b1;
    finish_cfg_handshake;
    check_condition(awaiting_publish,
                    "final commit alone enabled publication");
    send_publish_with_edge_capture(1'b1, 1'b0);
    check_published_m00(1'b1, 300);

    // ABORT hides a partial inactive generation and permits a clean restart.
    send_begin(1'b0);
    send_write(0, 0, 1'b0, 700);
    send_abort(1'b0);
    check_condition(!load_busy && !cfg_protocol_error &&
                    active_pose_version == 1'b1,
                    "abort preserved active epoch and allowed restart");
    load_all_regions(1'b0, 800);
    send_publish_with_edge_capture(1'b0, 1'b1);
    check_published_m00(1'b0, 800);

    // A regional accounting failure aborts preparation but preserves active.
    send_begin(1'b1);
    send_write(0, 0, 1'b1, 900);
    @(negedge clk);
    region_pose_accounting_error = 1'b1;
    @(posedge clk);
    #1;
    check_condition(cfg_protocol_error && !cfg_ready && !region_wr_req,
                    "regional accounting error fail-stop");
    check_condition(active_pose_valid && active_pose_version == 1'b0,
                    "regional error preserved published pose");

    // PUBLISH before all writes is a fatal protocol violation.
    reset_dut;
    send_begin(1'b1);
    @(negedge clk);
    drive_cfg(CFG_PUBLISH, 0, 0, 1'b1, 0);
    finish_cfg_handshake;
    check_condition(cfg_protocol_error && !active_pose_valid,
                    "early publish rejected");

    // Out-of-order region writes never reach a local pose table.
    reset_dut;
    send_begin(1'b0);
    commits_before_fault = write_commits;
    @(negedge clk);
    drive_cfg(CFG_WRITE, 1, 0, 1'b0, 400);
    #1;
    check_condition(!region_wr_req && cfg_ready,
                    "out-of-order write not forwarded");
    finish_cfg_handshake;
    check_condition(cfg_protocol_error &&
                    write_commits == commits_before_fault,
                    "out-of-order write fail-stop without commit");

    // An already active pose ID cannot be partially overwritten.
    reset_dut;
    load_all_regions(1'b0, 500);
    send_publish_with_edge_capture(1'b0, 1'b0);
    check_published_m00(1'b0, 500);
    send_begin(1'b0);
    check_condition(cfg_protocol_error && active_pose_valid &&
                    active_pose_version == 1'b0,
                    "active pose reload rejected");

    // A selected ready region that fails to return commit is fail-stop.
    reset_dut;
    send_begin(1'b0);
    commits_before_fault = write_commits;
    @(negedge clk);
    suppress_region_commit = 1'b1;
    drive_cfg(CFG_WRITE, 0, 0, 1'b0, 600);
    #1;
    check_condition(region_wr_req && cfg_ready && !region_wr_commit,
                    "missing-commit fault injected");
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;
    suppress_region_commit = 1'b0;
    check_condition(cfg_protocol_error && !active_pose_valid &&
                    write_commits == commits_before_fault,
                    "missing commit detected without index advance");

    // A commit without a selected request is also fail-stop.
    reset_dut;
    commits_before_fault = write_commits;
    @(negedge clk);
    force_spurious_commit = 1'b1;
    @(posedge clk);
    #1;
    force_spurious_commit = 1'b0;
    check_condition(cfg_protocol_error && !cfg_ready &&
                    write_commits == commits_before_fault,
                    "spurious commit detected without local write");

    if (errors == 0) begin
      $display("AFFINE_REGION_POSE_LOADER_PASS regions=%0d commits=%0d",
               REGION_COUNT, write_commits);
      $finish;
    end else begin
      $fatal(1, "AFFINE_REGION_POSE_LOADER_FAIL errors=%0d", errors);
    end
  end

  initial begin
    #500000;
    $fatal(1, "AFFINE_REGION_POSE_LOADER_TIMEOUT");
  end
endmodule
