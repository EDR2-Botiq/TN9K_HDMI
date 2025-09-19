################################################################################
# Tang Nano 9K HDMI TX Module - SDC Timing Constraints
# Target: GW1NR-9C FPGA
# Function: 800x480@60Hz HDMI Transmitter
################################################################################

################################################################################
# 1. Input Clocks
################################################################################

# Primary 27 MHz crystal oscillator input
create_clock -name clk_crystal -period 37.037 -waveform {0 18.518} [get_ports {I_clk}]

# Generated clocks (informational - Gowin will derive automatically)
# TMDS PLL: 27 MHz -> 162 MHz (period = 6.173 ns, exact calculation)
# Pixel Clock Divider: 162 MHz ÷ 5 -> 32.4 MHz (period = 30.864 ns, for 800x480@60Hz)

################################################################################
# 1a. Generated Clocks (Informational – tool may infer automatically)
################################################################################
# NOTE: Replace hierarchical pin paths with actual post-synthesis names if different.
# These are advisory so timing reports show proper derived domains.

# Simplified SDC for Gowin compatibility
# Complex generated clocks handled automatically by Gowin tools

# Simple divided audio toggle clock (exposed mainly for reference). If kept as a port,
# you can uncomment below after verifying instance names.
# create_generated_clock -name clk_audio -source [get_pins {u_hdmi_tx/u_clkdiv/clkout}] \
#     -divide_by 1050 [get_ports {clk_audio}]

################################################################################
# 2. Clock Constraints
################################################################################

# Note: Internal generated clocks are inferred by Gowin tools.
# Explicitly declare pixel and audio as asynchronous clock groups to
# suppress relationship warnings (TA1117/CK3000) and rely on CDC logic.
# set_clock_groups -asynchronous -group [get_clocks {clk_pixel}] -group [get_clocks {clk_audio}]

################################################################################
# 3. Basic Timing Constraints (Minimal for Gowin)
################################################################################

# HDMI outputs are source-synchronous (self-timed)
set_false_path -to [get_ports {O_tmds_clk_p O_tmds_clk_n O_tmds_data_p[*] O_tmds_data_n[*]}]

# Reset is asynchronous
set_false_path -from [get_ports {I_rst_n}]

# Note: Cross-domain timing handled automatically by design synchronization

################################################################################
# End of SDC File
################################################################################