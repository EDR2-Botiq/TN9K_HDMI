# Mixed-language build script for TN9K HDMI project
# Supports VHDL + SystemVerilog
# Use with: "C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe" build.tcl

open_project TN9K_HDMI_800x480.gprj

# Enable SystemVerilog support (Education version has limited options)
set_option -verilog_std sysv2017
# Mixed-mode and VHDL standard options not available in Education version

set_option -top_module TN9K_HDMI_800x480_top
run syn
run pnr