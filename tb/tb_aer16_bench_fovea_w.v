`ifndef WEIGHT_VAL
`define WEIGHT_VAL 3
`endif
`define TX aer_tx16_fovea
`define TX_PARAMS #(.WEIGHT(`WEIGHT_VAL))
`define TX_NAME "fovea(weighted)"
`include "aer16_bench_core.vh"
