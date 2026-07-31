`ifndef WEIGHT_VAL
`define WEIGHT_VAL 3
`endif
`define TX aer_tx16_fovea
`define TX_PARAMS #(.WEIGHT(`WEIGHT_VAL))
`define TX_NAME "fovea(weighted)"
`define HOTSPOT_NAME "hotspot=CORNER"
`include "hotspot_bench_core.vh"
