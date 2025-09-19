# Build Instructions for TN9K HDMI Project

This document provides detailed build instructions for the Tang Nano 9K HDMI project with 800x480@60Hz output.

## Prerequisites

### Hardware Requirements
- **Tang Nano 9K FPGA Board** (GW1NR-9C device)
- **HDMI Cable** and 800x480@60Hz compatible display
- **USB-C Cable** for programming and power

### Software Requirements
- **Gowin EDA Suite** v1.9.12 or later (required for mixed-language support)
- **Windows/Linux** development environment
- **Git** (optional, for version control)

## Project Structure

```
TN9K_HDMI/
├── src/
│   ├── TN9K_HDMI_800x480_top.vhd      # VHDL top-level entity
│   ├── demo_pattern_gen.vhd            # Pattern and audio generation
│   ├── hdmi_constants.vhd              # Timing constants for 800x480
│   ├── clocks/
│   │   ├── gowin_tmds_rpll.vhd         # 166.5MHz PLL configuration
│   │   ├── gowin_hdmi_clkdiv.vhd       # 33.3MHz pixel clock divider
│   │   └── *.ipc                       # IP Configurator files
│   └── hdmi/                           # SystemVerilog hdl-util core
│       ├── hdmi.sv                     # Main HDMI controller
│       ├── packet_picker.sv            # Packet scheduling
│       ├── packet_assembler.sv         # BCH error correction
│       ├── serializer.sv               # OSER10 serialization
│       ├── tmds_channel.sv             # TMDS encoding
│       └── *.sv                        # InfoFrame modules
├── tn9k_hdmi.cst                       # Pin constraints
├── tn9k_hdmi.sdc                       # Timing constraints
├── TN9K_HDMI_800x480.gprj              # Gowin project file
├── build_mixed.tcl                     # Build script
└── verify_hdmi.tcl                     # Verification script
```

## Build Process

### Method 1: Using Gowin IDE (Recommended)

1. **Open Project**
   ```
   File → Open → Select TN9K_HDMI_800x480.gprj
   ```

2. **Verify Mixed-Language Support**
   - Ensure Gowin IDE v1.9.12+ is installed
   - Check that both VHDL and SystemVerilog files appear in project

3. **Configure Build Options**
   - Go to **Tools → Options → Synthesis**
   - Set **Verilog Standard**: SystemVerilog 2017
   - Set **VHDL Standard**: VHDL 2008
   - Enable **Mixed Language** support

4. **Run Synthesis**
   ```
   Process → Run All
   ```
   Or step by step:
   - **Synthesis** (converts HDL to netlist)
   - **Place & Route** (physical implementation)
   - **Generate Bitstream** (creates .fs file)

### Method 2: Command Line Build

1. **Navigate to Project Directory**
   ```bash
   cd /path/to/TN9K_HDMI
   ```

2. **Run Build Script**
   ```bash
   "C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" build_mixed.tcl
   ```

3. **Check Results**
   ```bash
   "C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" verify_hdmi.tcl
   ```

## Clock Configuration Details

### PLL Settings (gowin_tmds_rpll.vhd)
- **Input Clock**: 27MHz (crystal)
- **FBDIV_SEL**: 36 (multiply by 37)
- **IDIV_SEL**: 5 (divide by 6)
- **Output**: 27MHz × 37 ÷ 6 = **166.5MHz TMDS**

### Clock Divider (gowin_hdmi_clkdiv.vhd)
- **Input**: 166.5MHz (from PLL)
- **DIV_MODE**: 5 (divide by 5)
- **Output**: 166.5MHz ÷ 5 = **33.3MHz pixel clock**

### Timing Results
- **Refresh Rate**: 33.3MHz ÷ (1056×525) = **60.023Hz**
- **Error**: +0.04% from ideal 60Hz (excellent!)

## Expected Build Outputs

### Successful Build Generates
```
impl/
├── gwsynthesis/
│   └── TN9K_HDMI_800x480.vg      # Synthesis netlist
├── pnr/
│   ├── TN9K_HDMI_800x480.fs      # Programming bitstream
│   ├── TN9K_HDMI_800x480.rpt.html # Resource usage report
│   └── TN9K_HDMI_800x480.tr.html  # Timing analysis report
└── temp/                          # Temporary build files
```

### Resource Usage Expectations
- **LUTs**: ~3000 (35% of GW1NR-9C)
- **Registers**: ~1200 (14% of GW1NR-9C)
- **BRAM**: Minimal usage (efficient packet generation)
- **PLLs**: 2/2 (TMDS PLL + Clock Divider)
- **OSER10**: 4/4 (3 data channels + 1 clock)

## Programming the FPGA

### SRAM Programming (Volatile, for Testing)
```bash
cd /path/to/TN9K_HDMI
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" \
  --device GW1NR-9C \
  --operation_index 2 \
  --fsFile "impl/pnr/TN9K_HDMI_800x480.fs"
```

### Flash Programming (Permanent)
```bash
cd /path/to/TN9K_HDMI
"C:\Gowin\Gowin_V1.9.12_x64\Programmer\bin\programmer_cli.exe" \
  --device GW1NR-9C \
  --operation_index 5 \
  --fsFile "impl/pnr/TN9K_HDMI_800x480.fs"
```

### Programming via Gowin Programmer GUI
1. **Open Gowin Programmer**
2. **Select Device**: GW1NR-9C
3. **Add File**: `impl/pnr/TN9K_HDMI_800x480.fs`
4. **Choose Operation**:
   - **SRAM Program**: For testing (volatile)
   - **Flash Erase → Flash Program**: For permanent installation
5. **Click Program**

## Verification and Testing

### LED Status Indicators
After programming, check the LEDs (active low):
- **LED 0 (OFF)**: PLL locked ✅
- **LED 1 (OFF)**: HDMI video active ✅
- **LED 2 (OFF)**: Audio enabled ✅
- **LEDs 3-5**: Pattern number in binary (cycling every 5s)

### HDMI Display Testing
1. **Connect 800x480 HDMI display**
2. **Verify video patterns**:
   - Color bars, gradients, checkerboard, etc.
   - Pattern changes every 5 seconds
   - No tearing or sync issues
3. **Test audio** (if display supports):
   - Should hear tone changing with each pattern

### Timing Analysis
Check timing reports in `impl/pnr/`:
- **Setup slack**: Must be > 0.5ns for 166.5MHz TMDS
- **Hold slack**: Must be > 0.1ns across all domains
- **Clock skew**: Should be minimal between clock domains

## Troubleshooting

### Common Build Issues

**Error: "Cannot find SystemVerilog files"**
- Solution: Ensure Gowin IDE v1.9.12+ with SystemVerilog support
- Check project file includes all .sv files with correct paths

**Error: "Mixed language not supported"**
- Solution: Upgrade to Gowin IDE v1.9.12 or later
- Enable mixed-language compilation in project settings

**Error: "PLL cannot achieve target frequency"**
- Solution: Verify PLL parameters in .ipc files
- Check that FBDIV=36, IDIV=5 for 166.5MHz output

### Common Runtime Issues

**No HDMI output**
- Check LED 0: If ON (active low), PLL not locked
- Check LED 1: If ON (active low), no video generation
- Verify HDMI cable and display compatibility

**Wrong refresh rate**
- Check timing calculations in hdmi_constants.vhd
- Verify pixel clock is 33.3MHz (not 30MHz or 25.2MHz)
- Ensure TMDS clock is exactly 5× pixel clock

**Audio not working**
- Check LED 2: If ON (active low), audio not enabled
- Verify display supports HDMI audio
- Check ACR packet generation in hdl-util core

### Debug Techniques

**Use Timing Analysis**
```bash
# Check timing report
open impl/pnr/TN9K_HDMI_800x480.tr.html
```

**Monitor Clock Frequencies**
- Add debug outputs for clock frequencies
- Use oscilloscope to verify clock rates
- Check PLL lock status signal

**Incremental Testing**
1. Test with video only (disable audio)
2. Test with simple patterns first
3. Add audio after video is stable
4. Verify InfoFrame transmission

## Advanced Configuration

### Changing Resolution
To modify for different resolutions:

1. **Update hdmi_constants.vhd**:
   ```vhdl
   constant H_VISIBLE : integer := 1024;  -- New width
   constant V_VISIBLE : integer := 768;   -- New height
   -- Update total timings accordingly
   ```

2. **Recalculate PLL**:
   - New pixel clock = (H_TOTAL × V_TOTAL × 60Hz)
   - New TMDS clock = pixel clock × 5
   - Update FBDIV/IDIV for new TMDS frequency

3. **Update hdmi.sv**:
   ```systemverilog
   localparam SCREEN_WIDTH = 1024;
   localparam SCREEN_HEIGHT = 768;
   ```

4. **Update constraint files**:
   - Modify .sdc for new clock frequencies
   - Update .cst if needed

### Audio Customization
To modify audio generation:

1. **Edit demo_pattern_gen.vhd**:
   - Change `DEMO_TONE_FREQ` for different frequencies
   - Modify pattern-specific audio generation

2. **External Audio Input**:
   - Replace tone generator with external PCM source
   - Ensure proper clock domain crossing
   - Maintain 48kHz sample rate for HDMI compliance

## Performance Optimization

### Resource Usage
- **LUT Optimization**: Use efficient coding practices
- **Register Optimization**: Minimize pipeline stages where possible
- **Memory Usage**: hdl-util already optimizes packet storage

### Timing Optimization
- **Clock Domain Isolation**: Keep fast clocks separate
- **Pipeline Deep Paths**: Add registers for timing closure
- **Constraint Accuracy**: Ensure .sdc reflects actual requirements

### Power Optimization
- **Clock Gating**: Disable unused clock domains
- **Dynamic Frequency**: Scale clocks based on requirements
- **Sleep Modes**: Power down unused blocks when possible

## Support and Resources

### Documentation
- **Gowin Documentation**: Synthesis and implementation guides
- **HDMI Specification**: Timing and protocol requirements

### Community
- **Gowin Forums**: Technical support and discussions
- **FPGA Communities**: Reddit, Discord, forums

### Hardware References
- **Tang Nano 9K User Manual**: Pin assignments and specifications
- **GW1NR-9C Datasheet**: Device capabilities and limitations
- **HDMI Specification**: Timing and protocol requirements

---

**Note**: This project uses a mixed-language design with VHDL top-level and SystemVerilog HDMI core for optimal performance and standards compliance.