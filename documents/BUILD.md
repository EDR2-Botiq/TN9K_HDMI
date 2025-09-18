# Building and Programming the TN9K HDMI Project

This guide provides the steps to synthesize the VHDL code into a bitstream file and program it to the Tang Nano 9K FPGA.

## Prerequisites

- **[Gowin EDA](http://www.gowinsemi.com/en/support/download_eda/)** (v1.9.12 or later required)
- **Tang Nano 9K** with USB-C programming cable
- **HDMI Display** supporting 640x480@60Hz

## Build Methods

### Method 1: Gowin IDE GUI (Recommended for Beginners)

1. **Open project in Gowin IDE**:
   ```bash
   gw_ide TN9K_HDMI.gprj
   ```

2. **Synthesize**:
   - Press F7 or click "Synthesis" button
   - Check for errors in console

3. **Place & Route**:
   - Press F8 or click "Place & Route"
   - Review timing report for violations

4. **Generate Bitstream**:
   - Automatic after successful Place & Route
   - Output: `impl/pnr/TN9K_HDMI.fs`

### Method 2: Command-Line Build

#### Using TCL Shell
1. Open terminal in project root directory
2. Run Gowin shell with TCL script:
   ```bash
   "C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" -c "open_project TN9K_HDMI.gprj; run syn; run pnr"
   ```

#### Build Output
Successful build creates:
- `impl/pnr/TN9K_HDMI.fs` - Bitstream file
- `impl/pnr/TN9K_HDMI.tr.html` - Timing report
- `impl/gwsynthesis/TN9K_HDMI_syn.rpt.html` - Synthesis report

## Programming the FPGA

### Method 1: Gowin Programmer GUI

1. **Open Gowin Programmer**:
   - Launch from Gowin IDE: Tools → Programmer
   - Or standalone: `programmer_gui.exe`

2. **Connect Tang Nano 9K** via USB-C

3. **Scan for Device**:
   - Click "Scan" button
   - Should detect: GW1NR-9C

4. **Load Bitstream**:
   - Browse to `impl/pnr/TN9K_HDMI.fs`

5. **Program**:
   - Select "SRAM Program" for testing (volatile)
   - Or "embFlash Erase,Program" for permanent

### Method 2: Command-Line Programming

#### Step 1: Verify FPGA Connection
```bash
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --scan
```
Expected output:
```
Device Info:
  Family: GW1NR
  Name: GW1N-9C GW1NR-9C
  ID: 0x1100481B
```

#### Step 2: Program to SRAM (Volatile - For Testing)
```bash
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 2 --fsFile "impl\pnr\TN9K_HDMI.fs"
```

#### Step 3: Program to Flash (Permanent - Optional)
```bash
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 5 --fsFile "impl\pnr\TN9K_HDMI.fs"
```

### Programming Operation Codes
- **operation_index 2**: SRAM Program (volatile, for testing)
- **operation_index 5**: embFlash Erase,Program (permanent)
- **operation_index 6**: embFlash Erase,Program,Verify (permanent with verification)

### Expected Programming Output
```
Programming...: [#########################] 100%
User Code is: 0x0000C293
Status Code is: 0x0003F020
Finished.
Cost 3.6 second(s)
```

## Hardware Setup

### Required Hardware
- **Tang Nano 9K FPGA Board** (GW1NR-9C)
- **HDMI Display** supporting 640x480@60Hz
- **HDMI Cable**
- **USB-C Cable** for power and programming

### Quick Test After Programming

1. **Connect HDMI cable** between Tang Nano 9K and display
2. **Power on** via USB-C
3. **Check LED indicators**:
   - LED 0: Should be ON (PLL locked)
   - LED 1: Should be ON (HDMI active)
   - LED 2: Should be ON (clocks valid)
   - LEDs 3-5: Show current pattern number (changes every 5 seconds)

### Demo Patterns
The HDMI output automatically cycles through 6 test patterns every 5 seconds:
- Pattern 0: TV Color Bars
- Pattern 1: Checkerboard
- Pattern 2: RGB Gradient
- Pattern 3: Grid/Crosshatch
- Pattern 4: Moving Box Animation
- Pattern 5: Diagonal Rainbow Stripes

### Troubleshooting
- **No HDMI signal**: Check HDMI cable and display compatibility
- **No keyboard response**: Verify PS/2 connections and keyboard compatibility
- **Game not starting**: Re-program FPGA or check power connections
- **Build errors**: Ensure all VHDL files are VHDL-93 compatible

### Expected Programming Output
```
Programming...: [#########################] 100%
User Code is: 0x0000C293
Status Code is: 0x0003F020
Finished.
Cost 3.6 second(s)
```
