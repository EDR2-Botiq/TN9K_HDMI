---
allowed-tools: Bash
description: Build HDMI 800x480 project and flash to SRAM or Flash memory
argument-hint: [sram|flash] (defaults to sram)
---

Build the Tang Nano 9K HDMI 800x480 project and program to device with progress feedback.

## Stage 1: Building 800x480 project
!`echo "=== STAGE 1/3: Building HDMI 800x480 project ===" && cd /e/OneDrive/Desktop/FPGA/TN9K_HDMI && "C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" build.tcl`

## Stage 2: Checking 800x480 bitstream
!`echo "=== STAGE 2/3: Verifying bitstream ===" && ls -la "E:\OneDrive\Desktop\FPGA\TN9K_HDMI\impl\pnr\TN9K_HDMI_800x480.fs"`

## Stage 3: Programming device with 800x480 bitstream
{% if args[0] == "flash" %}
!`echo "=== STAGE 3/3: Programming to Flash (permanent) ===" && cd /e/OneDrive/Desktop/FPGA/TN9K_HDMI && "C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 5 --fsFile "E:\OneDrive\Desktop\FPGA\TN9K_HDMI\impl\pnr\TN9K_HDMI_800x480.fs"`
{% else %}
!`echo "=== STAGE 3/3: Programming to SRAM (volatile) ===" && cd /e/OneDrive/Desktop/FPGA/TN9K_HDMI && "C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 2 --fsFile "E:\OneDrive\Desktop\FPGA\TN9K_HDMI\impl\pnr\TN9K_HDMI_800x480.fs"`
{% endif %}

!`echo "=== BUILD-FLASH 800x480 COMPLETE ==="`