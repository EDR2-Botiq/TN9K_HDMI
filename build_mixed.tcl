# Mixed-language build script for TN9K HDMI with hdl-util core
# Compiles both VHDL and SystemVerilog files for Gowin IDE

# Set device and project
set_device -device_version C GW1NR-9C

# Add SystemVerilog HDMI core files
add_file -type verilog src/hdmi/hdmi.sv
add_file -type verilog src/hdmi/packet_picker.sv
add_file -type verilog src/hdmi/packet_assembler.sv
add_file -type verilog src/hdmi/serializer.sv
add_file -type verilog src/hdmi/tmds_channel.sv
add_file -type verilog src/hdmi/audio_sample_packet.sv
add_file -type verilog src/hdmi/audio_clock_regeneration_packet.sv
add_file -type verilog src/hdmi/auxiliary_video_information_info_frame.sv
add_file -type verilog src/hdmi/audio_info_frame.sv
add_file -type verilog src/hdmi/source_product_description_info_frame.sv

# Add VHDL files
add_file -type vhdl src/hdmi_constants.vhd
add_file -type vhdl src/demo_pattern_gen.vhd
add_file -type vhdl src/clocks/gowin_tmds_rpll.vhd
add_file -type vhdl src/clocks/gowin_hdmi_clkdiv.vhd
add_file -type vhdl src/TN9K_HDMI_800x480_top.vhd

# Add constraint files
add_file -type cst tn9k_hdmi.cst
add_file -type sdc tn9k_hdmi.sdc

# Set top-level module
set_option -top_module TN9K_HDMI_800x480_top

# Set language options for mixed design
set_option -verilog_std sysv2017
set_option -vhdl_std vhdl2008

# Define compiler directive for Gowin OSER10 support
set_option -define GW_IDE

# Run synthesis
run_synthesis

# Place and route
run_pnr

# Generate programming file
run_bitstream

puts "Build completed. Check impl/pnr/ for output files."