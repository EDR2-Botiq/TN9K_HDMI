# Build Instructions

Quick guide for building and programming the Tang Nano 9K HDMI project.

## Prerequisites

- **Gowin EDA v1.9.12+**
- **Tang Nano 9K** with USB cable

## Build

Navigate to project directory and run:

```bash
"C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe" build.tcl
```

This generates the bitstream: `impl/pnr/TN9K_HDMI_800x480.fs`

## Program

### SRAM (Volatile, for testing)
```bash
"C:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 2 --fsFile "E:\OneDrive\Desktop\FPGA\TN9K_HDMI\impl\pnr\TN9K_HDMI_800x480.fs"
```

### Flash (Permanent)
```bash
"C:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 5 --fsFile "E:\OneDrive\Desktop\FPGA\TN9K_HDMI\impl\pnr\TN9K_HDMI_800x480.fs"
```

## Verification

After programming, check LEDs:
- **LED 0 OFF**: PLL locked ✓
- **LED 1 OFF**: Video active ✓
- **LED 2 OFF**: Audio enabled ✓
- **LEDs 3-5**: Pattern number (cycles every 5s)
