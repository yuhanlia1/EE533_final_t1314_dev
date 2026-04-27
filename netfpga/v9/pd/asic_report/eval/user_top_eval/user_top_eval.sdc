# Auto-generated stub SDC for later synthesis / P&R.
create_clock -name core_clk -period 10.000 [get_ports clk]
set_input_delay 0.0 -clock core_clk [all_inputs]
set_output_delay 0.0 -clock core_clk [all_outputs]
# Refine IO delays and false/multicycle paths after library + interface timing are known.
