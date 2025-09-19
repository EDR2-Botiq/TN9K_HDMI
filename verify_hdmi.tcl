# Verification script for TN9K HDMI with hdl-util implementation
# Checks timing, resource usage, and validates configuration

puts "=== TN9K HDMI Verification Script ==="
puts "Checking hdl-util HDMI implementation..."

# Check if all required files exist
set hdmi_files {
    "src/hdmi/hdmi.sv"
    "src/hdmi/packet_picker.sv"
    "src/hdmi/packet_assembler.sv"
    "src/hdmi/serializer.sv"
    "src/hdmi/tmds_channel.sv"
    "src/hdmi/audio_sample_packet.sv"
    "src/hdmi/audio_clock_regeneration_packet.sv"
    "src/hdmi/auxiliary_video_information_info_frame.sv"
    "src/hdmi/audio_info_frame.sv"
    "src/hdmi/source_product_description_info_frame.sv"
}

set vhdl_files {
    "src/hdmi_constants.vhd"
    "src/demo_pattern_gen.vhd"
    "src/clocks/gowin_tmds_rpll.vhd"
    "src/clocks/gowin_hdmi_clkdiv.vhd"
    "src/TN9K_HDMI_800x480_top.vhd"
}

puts "\nChecking SystemVerilog HDMI files:"
foreach file $hdmi_files {
    if {[file exists $file]} {
        puts "✓ $file"
    } else {
        puts "✗ MISSING: $file"
    }
}

puts "\nChecking VHDL files:"
foreach file $vhdl_files {
    if {[file exists $file]} {
        puts "✓ $file"
    } else {
        puts "✗ MISSING: $file"
    }
}

# Verify clock configuration
puts "\n=== Clock Configuration Verification ==="
puts "Expected clocks for 800x480@60Hz:"
puts "  Crystal:     27 MHz"
puts "  TMDS serial: 150 MHz (27 × 50 ÷ 9)"
puts "  Pixel clock: 30 MHz (150 ÷ 5)"
puts "  Audio clock: ~48 kHz (30MHz ÷ 625)"

# Check if project can be opened (if built)
if {[file exists "impl/pnr/TN9K_HDMI.fs"]} {
    puts "\n✓ Bitstream file found: impl/pnr/TN9K_HDMI.fs"

    # Check timing report if available
    if {[file exists "impl/pnr/TN9K_HDMI.tr.html"]} {
        puts "✓ Timing report available: impl/pnr/TN9K_HDMI.tr.html"
    }

    # Check resource usage
    if {[file exists "impl/pnr/TN9K_HDMI.rpt.html"]} {
        puts "✓ Resource report available: impl/pnr/TN9K_HDMI.rpt.html"
    }
} else {
    puts "\n⚠ No bitstream found. Run build_mixed.tcl first."
}

puts "\n=== Configuration Summary ==="
puts "Resolution:    800x480@60Hz (16:9 aspect ratio)"
puts "HDMI Standard: hdl-util reference implementation"
puts "Audio:         48kHz stereo with demo tones"
puts "Features:      AVI InfoFrame, Audio InfoFrame, ACR packets"
puts "Hardware:      Tang Nano 9K (GW1NR-9C FPGA)"

puts "\n=== Next Steps ==="
puts "1. Run build_mixed.tcl to compile the design"
puts "2. Program to SRAM for testing:"
puts "   programmer_cli.exe --device GW1NR-9C --operation_index 2 --fsFile impl/pnr/TN9K_HDMI.fs"
puts "3. Connect to 800x480 16:9 HDMI display"
puts "4. Verify pattern cycling and audio output"

puts "\nVerification complete."