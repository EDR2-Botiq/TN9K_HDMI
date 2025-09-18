# Building and Flashing the Bitstream

This guide provides the steps to synthesize the VHDL code into a bitstream file and flash it to the Tang Nano 9K FPGA.

## Prerequisites

- **[Gowin EDA](http://www.gowinsemi.com/en/support/download_eda/)** (v1.9.10 or later)
- **Tang Nano 9K** with USB programming cable



## Command-Line Build and Flash (Verified Working Method)

### Prerequisites

- **Gowin EDA v1.9.12** or later installed
- **Tang Nano 9K** connected via USB
- **No PATH requirements** - using absolute paths for reliability

### Build (Verified Method)

#### Option 1: Using TCL Shell (Recommended)
1. Open terminal in project root directory
2. Use absolute path to gw_sh.exe:
   ```bash
   "C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" build.tcl
   ```

#### Option 2: Using provided batch scripts
1. Run the batch script:
   ```bash
   run_build.bat
   ```

#### Build TCL Script (build.tcl)
The project includes a working TCL build script with corrected Gowin TCL commands:
```tcl
open_project TN9K-Invaders.gprj
run syn
run pnr
```

**Note**: Uses correct `run syn` and `run pnr` syntax (not `process run` which is incorrect).

### Flash (Verified Working Method)

#### Step 1: Verify FPGA Connection
1. Connect Tang Nano 9K via USB
2. Scan for device:
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

#### Step 2: Program FPGA (SRAM - Volatile)
**Use absolute paths for both programmer and bitstream file:**
```bash
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 2 --fsFile "E:\OneDrive\Desktop\FPGA\YN9K_SI\impl\pnr\TN9K-Invaders.fs"
```

#### Step 3: Program to Flash (Permanent - Optional)
To make the configuration permanent:
```bash
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" --device GW1NR-9C --operation_index 5 --fsFile "E:\OneDrive\Desktop\FPGA\YN9K_SI\impl\pnr\TN9K-Invaders.fs"
```

#### Alternative: Use Batch Script
Run the provided batch file:
```bash
flash.bat
```

#### Programming Operation Codes
- **operation_index 2**: SRAM Program (volatile, for testing)
- **operation_index 5**: embFlash Erase,Program (permanent)
- **operation_index 6**: embFlash Erase,Program,Verify (permanent with verification)

### Critical Notes
- **Always use absolute paths** for both programmer executable and bitstream file
- **SRAM programming** is volatile (lost on power cycle) but faster for development
- **Flash programming** is permanent but takes longer
- Successful programming shows progress bar and "Finished" message

## Hardware Setup and Game Controls

### Required Hardware
- **HDMI Display**: 640x480@60Hz output (most monitors support this)
- **PS/2 Keyboard**: For game controls (connected to pins 76/77)
- **USB Power**: Via USB-C cable to Tang Nano 9K
- **Audio** (Optional): External amplifier + speakers connected to pins 33/34

### Enhanced Video System Architecture (2025 Update)
This implementation uses **direct VRAM processing** with enhanced features:
- **Direct VRAM Access**: Real-time processing from shared 8KB system RAM
- **2-Stage Pipeline**: Compensates for BRAM latency while maintaining authentic timing
- **Enhanced Synchronization**: Line start and frame start strobes for precise timing
- **Test Pattern Generator**: Built-in arcade test patterns for debugging
- **Authentic Layout**: Preserves original Space Invaders memory organization
- **Character-based**: Original 8×8 character patterns with real-time color overlays

### Game Controls
- **Arrow Keys**: Move left/right
- **Space Bar**: Fire missile
- **Enter Key**: Start game
- **ESC**: Reset (if implemented)

### Starting the Game
1. Connect HDMI cable between Tang Nano 9K and display
2. Connect PS/2 keyboard to pins 76 (CLK) and 77 (DATA)
3. Power on Tang Nano 9K via USB
4. Game should start automatically on HDMI display
5. Press Enter to begin playing

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
