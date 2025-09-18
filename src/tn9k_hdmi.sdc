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