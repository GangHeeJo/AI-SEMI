# Tighter clock target for timing optimization on the base design.
# base's first run at 5ns had WNS=2883ps (critical path only ~2.117ns) —
# this constraint pushes Genus to actually optimize instead of coasting on slack.
create_clock -name clk -period 2.200 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]
set_input_delay  -clock clk 0.250 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk 0.250 [all_outputs]
set_load 0.010 [all_outputs]
