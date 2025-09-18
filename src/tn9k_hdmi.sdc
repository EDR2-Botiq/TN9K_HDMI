################################################################################
# Tang Nano 9K HDMI TX Module - SDC Timing Constraints
# Target: GW1NR-9C FPGA
# Function: 640x480@60Hz HDMI Transmitter
################################################################################

################################################################################
# 1. Input Clocks
################################################################################

# Primary 27 MHz crystal oscillator input
create_clock -name clk_crystal -period 37.037 -waveform {0 18.518} [get_ports {clk_crystal}]

# Generated clocks (informational - Gowin will derive automatically)
# TMDS PLL: 27 MHz -> 126 MHz (period = 7.937 ns, exact calculation)
# Pixel Clock Divider: 126 MHz ÷ 5 -> 25.2 MHz (period = 39.683 ns, exact for VESA timing)

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
# 2. Clock Constraints (Primary Input Only)
################################################################################

# Note: Internal clocks handled automatically by Gowin tools
# WARNING TA1132 about undetermined clocks is normal and CANNOT be eliminated

################################################################################
# 3. Basic Timing Constraints (Minimal for Gowin)
################################################################################

# HDMI outputs are source-synchronous (self-timed)
set_false_path -to [get_ports {hdmi_tx_clk_p hdmi_tx_clk_n hdmi_tx_p[*] hdmi_tx_n[*]}]

# Reset is asynchronous
set_false_path -from [get_ports {reset_n}]

# Note: Cross-domain timing handled automatically by design synchronization

################################################################################
# End of SDC File
################################################################################