# TN9K HDMI - Tang Nano 9K HDMI Library

A complete HDMI transmitter implementation for the Tang Nano 9K FPGA board featuring auto-cycling demo patterns, stable HDMI audio (48 kHz using VIC20Nano packet infrastructure) and extensive debug capabilities.

## Overview

This project provides a reusable HDMI transmitter IP core for the Tang Nano 9K FPGA development board. The library outputs 640x480@60Hz video over HDMI using TMDS encoding and includes 6 built-in test patterns with automatic cycling, plus comprehensive debug and monitoring features.

## Features

- **HDMI Digital Video Output** at 640x480@60Hz using TMDS encoding
- **Stable HDMI Audio Support** VIC20Nano packet infrastructure with TERC4 + ACR
- **6 Auto-Cycling Demo Patterns** with 5-second intervals
- **Comprehensive Debug System** with LED status indicators
- **Robust Clock Generation** with debounced PLL lock detection
- **Timing Validation** with frame rate and sync monitoring
- **Manual Pattern Override** capability
- **Reusable IP Core** with standardized interfaces
- **Tang Nano 9K Optimized** using ELVDS_OBUF and OSER10 primitives

## Hardware Requirements

- **Tang Nano 9K FPGA Board** (GW1NR-9C)
- **HDMI Display** or monitor supporting 640x480@60Hz
- **HDMI Cable**
- **Power Supply** for Tang Nano 9K (USB or external)

## Demo Patterns

The library includes 6 built-in test patterns that automatically cycle every 5 seconds:

| Pattern | Description | Purpose |
|---------|-------------|---------|
| **0** | Classic TV Color Bars | Standard broadcast test pattern |
| **1** | Checkerboard (8x8) | Pixel accuracy and sharpness |
| **2** | RGB Gradient | Color range and gradient testing |
| **3** | Grid/Crosshatch | Geometric accuracy and alignment |
| **4** | Moving Animated Box | Motion testing and frame rate |
| **5** | Diagonal Rainbow Stripes | Color spectrum validation |

## LED Debug Display

The 6 LEDs on the Tang Nano 9K provide comprehensive status information (all active low):

| LED | Function | ON Status | Debug Purpose |
|-----|----------|-----------|---------------|
| **0** | PLL Stable Lock | PLL locked >40ms | Critical: must be ON |
| **1** | HDMI Active | Generating pixels | Video output health |
| **2** | Audio Path Enabled | Audio mux active | Confirms audio build variant |
| **3** | Pattern Bit 2 | Pattern MSB | Current pattern ID (binary) |
| **4** | Pattern Bit 1 | Pattern middle | Current pattern ID (binary) |
| **5** | Pattern Bit 0 + Frame | Pattern LSB + 60Hz | Pattern ID + frame rate |

### LED Status Interpretation:

**Healthy System** (all working):
- LED 0: ON (PLL stable)
- LED 1: ON (HDMI active)
- LED 2: ON (Audio enabled)
- LEDs 3-5: Change every 5 seconds showing pattern in binary

**Troubleshooting**:
- **LED 0 OFF**: PLL not stable - check 27MHz crystal or power supply
- **LED 1 OFF**: No HDMI output - TMDS encoding issue or cable problem
- **LED 2 OFF**: Audio path disabled (unexpected in current build) – check `audio_enable` and packetizer
- **LEDs 3-5 stuck**: Pattern generator not cycling - reset or timing issue

## Project Architecture

### Clock Architecture

The system uses a precise clock hierarchy for HDMI compliance:

| Clock Signal | Frequency | Purpose |
|-------------|-----------|---------|
| `clk_crystal` | 27 MHz | Crystal oscillator input |
| `clk_tmds_serial` | 126.000 MHz | TMDS serialization (27 MHz × 14 ÷ 3) |
| `clk_pixel` | 25.200 MHz | Pixel clock (÷5) – close to legacy 25.175 MHz VGA spec (≈0.1% error) |

### Directory Structure

```
TN9K_HDMI/
├── src/                                    # Source files
│   ├── TN9K_HDMI_top.vhd                  # Top-level (video + audio + patterns)
│   ├── demo_pattern_gen.vhd               # 6-pattern generator + audio tone source
│   ├── hdmi_tx_640x480.vhd                # Integrated transmitter (video/audio mux)
│   ├── hdmi_packet_picker.vhd             # VIC20Nano packet scheduling system
│   ├── hdmi_packet_assembler.vhd          # BCH error correction and packet assembly
│   ├── hdmi_audio_sample_packet.vhd       # Audio sample packet generator
│   ├── hdmi_constants.vhd                 # Centralized timing and audio constants
│   ├── hdmi_audio_acr.vhd                 # ACR generator (N / CTS)
│   ├── hdmi_terc4.vhd                     # 4-bit to 10-bit TERC4 encoding table
│   ├── hdmi_timing.vhd                    # 640x480@60Hz timing generator
│   ├── tmds_encoder.vhd                   # TMDS 8b/10b encoding logic
│   ├── clocks/                            # Clock generation components
│   │   ├── gowin_tmds_rpll.vhd           # 126.000 MHz TMDS PLL
│   │   ├── gowin_tmds_rpll.ipc           # PLL IP configuration
│   │   ├── gowin_hdmi_clkdiv.vhd         # 25.200 MHz pixel clock divider
│   │   └── gowin_hdmi_clkdiv.ipc         # Clock divider IP config
│   ├── tn9k_hdmi.cst                      # Pin constraints for Tang Nano 9K
│   └── tn9k_hdmi.sdc                      # Timing constraints
├── documents/                              # Documentation
│   ├── HDMI_IMPLEMENTATION_GUIDE.md       # Detailed implementation guide
│   ├── BUILD.md                           # Build instructions
│   └── Tang_Nano_9K_Complete_Reference.md # Board reference
├── impl/                                   # Build artifacts (auto-generated, git-ignored)
├── TN9K_HDMI.gprj                         # Gowin IDE project file
└── README.md                              # This file
```

### Key Components

#### 1. **Top Module** (`TN9K_HDMI_top.vhd`)
- Integrates video pipeline, audio packetizer, pattern generator, debug
- Manages clock generation via Gowin PLLs with monitoring
- Provides LED status and pattern control

#### 2. **Demo Pattern Generator** (`demo_pattern_gen.vhd`)
- Generates 6 different test patterns at 640x480 resolution
- Auto-cycles every 5 seconds with precise timing
- Supports manual pattern override
- Includes animated patterns for motion testing

#### 3. **Audio Path** (`hdmi_audio_acr.vhd`, `hdmi_packet_picker.vhd`, `hdmi_terc4.vhd`)

- ACR (N/CTS) generation for 48 kHz sync @ 25.200 MHz pixel clock
- TERC4 4->10 symbol mapping with registered inputs for signal stability
- VIC20Nano packet infrastructure using efficient case statements (no large sparse arrays)
- BCH error correction and proper packet assembly
- Audio Sample Packets with IEC 60958 formatting
- Pattern-specific demo tones integrated into pattern generator
- Fixed synthesis issues for stable video + audio operation

#### 4. **TMDS Encoding** (`tmds_encoder.vhd`)

- 8b/10b TMDS conversion with basic DC balance
- Optional pipeline register (generic `PIPELINE_BALANCE`) for higher pixel clocks
- Serialized via OSER10 then ELVDS_OBUF for differential output

#### 4. **Timing Generator** (`hdmi_timing.vhd`)

- Standard 640x480@60Hz VESA timing
- Generates HSync, VSync, and Data Enable signals
- Provides pixel coordinates for pattern generation
- Frame start indicator for synchronization

## Building the Project

### Prerequisites

1. **Gowin IDE** (v1.9.12 or later recommended)
2. **Tang Nano 9K Board** with USB-C cable
3. **HDMI Cable and Display** supporting 640x480@60Hz

### Build Steps

1. **Open project in Gowin IDE**:

   ```bash
   # Launch Gowin IDE
   gw_ide TN9K_HDMI.gprj
   ```

2. **Verify project settings**:
   - **Device**: GW1NR-9C
   - **Package**: QN88PC6/I5
   - **Speed**: -6
   - **Top-level**: `TN9K_HDMI_top`

3. **Synthesize and build**:
   - Run Synthesis (F7) - should complete without errors
   - Run Place & Route - check timing report
   - Generate Bitstream - creates `.fs` file

4. **Program the Tang Nano 9K**:
   - Connect Tang Nano 9K via USB-C
   - Open Gowin Programmer
   - Load bitstream file
   - Program device

### Quick Test

After programming:

1. **Connect HDMI** cable to display
2. **Check LED 0** - should be ON (PLL locked)
3. **Check LED 1** - should be ON (HDMI active)
4. **Check LED 2** - should be ON (Audio enabled)
5. **Observe patterns** - should cycle every 5 seconds
6. (Optional) Verify continuous tone; multi-packet audio should register on more displays now (still demo framing)

## Manual Pattern Selection

Pattern selection can be overridden by setting `pattern_select` signals:

| Input | Pattern | Description |
|-------|---------|-------------|
| "000" | Auto Mode | Cycles through all patterns |
| "001" | Pattern 1 | Checkerboard |
| "010" | Pattern 2 | RGB Gradient |
| "011" | Pattern 3 | Grid/Crosshatch |
| "100" | Pattern 4 | Moving Animation |
| "101" | Pattern 5 | Rainbow Stripes |

## Pin Assignments

Key pin assignments for Tang Nano 9K:

| Signal | Pin | Description |
|--------|-----|-------------|
| `clk_crystal` | 52 | 27 MHz crystal |
| `I_RESET` | 4 | Reset button (active low) |
| `led[0-5]` | 10-16 | Debug status LEDs |
| `hdmi_tx_clk_p/n` | 69/68 | HDMI clock differential |
| `hdmi_tx_p[0]/n[0]` | 71/70 | HDMI blue channel |
| `hdmi_tx_p[1]/n[1]` | 73/72 | HDMI green channel |
| `hdmi_tx_p[2]/n[2]` | 75/74 | HDMI red channel |

Complete pin constraints are defined in `src/tn9k_hdmi.cst`.

## Technical Details

### HDMI Video Pipeline

The design implements a complete HDMI transmitter pipeline:

1. **Pattern Generator** creates 640×480 @ 25.175MHz (24-bit RGB)
2. **HDMI Timing Generator** provides standard VGA timing with sync signals
3. **TMDS Encoders** convert 24-bit RGB to 10-bit encoded data per channel
4. **OSER10 Serializers** output high-speed differential pairs for HDMI
5. **ELVDS_OBUF** provides differential signaling for Tang Nano 9K

#### HDMI Video Specifications

- **Resolution**: 640×480 pixels (VGA standard)
- **Color**: 24-bit RGB (16.7 million colors)
- **Pixel Clock**: 25.200 MHz (close to 25.175 MHz legacy VGA; chosen for clean divider from 27 MHz)
- **Sync**: Separate HSync (31.469 kHz) and VSync (59.934 Hz) signals
- **Generated by**: Hardware timing generators and pattern logic

#### Pattern Generation Details

- **Test Patterns**: 6 different patterns for comprehensive testing
- **Auto-Cycling**: Patterns change every 5 seconds automatically
- **Manual Override**: Can select specific patterns via input pins
- **Animation Support**: Moving elements for motion testing

### Clock Generation

The HDMI implementation uses Gowin-recommended clock architecture:

- **Input Clock**: 27 MHz crystal oscillator
- **TMDS PLL** (`Gowin_TMDS_rPLL`): Generates 126.000 MHz TMDS clock (27 × 14 ÷ 3)
- **Clock Divider** (`Gowin_HDMI_CLKDIV`): Produces 25.200 MHz pixel clock (÷5)

This (126 / 5) approach trades a tiny frequency delta (~0.1%) for simpler synthesis closure and integer ratios. Most monitors tolerate the deviation; retarget to the 25.175 MHz exact path by adjusting PLL parameters if strict compliance is required.

An SDC now defines generated clocks (`clk_tmds`, `clk_pixel`) for clearer timing analysis.

### HDMI Output Method

**Important**: Tang Nano 9K uses **ELVDS_OBUF emulated differential** signaling:

- ELVDS_OBUF primitives create differential signals from single-ended
- Automatic polarity inversion on negative outputs
- OSER10 primitives handle 10:1 TMDS serialization at 125.875 MHz

## Audio Implementation Notes

| Aspect | Current Implementation | Upgrade Path |
|--------|------------------------|--------------|
| Sample Buffering | 64-sample FIFO | Increase depth / dual-clock FIFO if external source domain differs |
| Packets per Frame | Distributed across vertical blank (configurable) | Add horizontal blank scheduling for full 800 samples/frame |
| Waveform | Square tone (phase accumulator) | Replace with PCM stream / DDS sine LUT |
| ACR | One per frame | Periodic verification / regenerate at spec cadence |
| InfoFrames | Not implemented | Add Audio InfoFrame + AVI InfoFrame for compliance |
| Pixel Clock | 25.200 MHz variant | Adjust PLL to 25.175 path for exact VGA timing |
| TMDS Encoder | Optional pipeline disabled | Enable `PIPELINE_BALANCE` for higher resolutions |

To reach fully spec-compliant continuous LPCM: extend scheduler to emit packets in both vertical and horizontal blanking or increase packets per vblank while respecting guard band limits, and ensure total audio sample words ≈ (48,000 / 60) = 800 per frame.

## Troubleshooting Guide

### LED-Based Diagnosis

Use the LED indicators to quickly identify issues:

**Normal Operation** (all LEDs working):

```text
LED 0: ON  (PLL stable and locked)
LED 1: ON  (HDMI actively outputting video)
LED 2: ON  (Clock timing validated)
LEDs 3-5: Change every 5 seconds (pattern cycling)
```

### Common Issues and Solutions

#### 1. **No Display Output**

**LED 0 OFF** - PLL Not Locked:

- **Check**: 27MHz crystal oscillator
- **Check**: Power supply voltage (3.3V, 1.8V rails)
- **Check**: Board grounding and connections
- **Solution**: Verify crystal is oscillating with scope

**LED 1 OFF, LED 0 ON** - HDMI Not Active:

- **Check**: HDMI cable connection
- **Check**: Display compatibility (some don't support 640x480)
- **Check**: TMDS encoding in synthesis report
- **Solution**: Try different display or cable

**LED 2 OFF, LEDs 0,1 ON** - Clock Timing Issues:

- **Check**: Clock constraints properly loaded (.sdc file)
- **Check**: Timing analysis reports
- **Solution**: Review clock generation settings

#### 2. **Pattern Issues**

**Patterns Not Changing** (LEDs 3-5 stuck):

- **Check**: Reset signal stability
- **Check**: Pattern counter in debug
- **Solution**: Monitor frame_start signal with analyzer

**Wrong Colors or Distortion**:

- **Check**: RGB bit ordering in constraints
- **Check**: TMDS encoding logic
- **Solution**: Verify channel mapping (R=2, G=1, B=0)

#### 3. **Synthesis Issues**

**"ELVDS_OBUF not found"**:

- **Cause**: Incorrect Gowin IDE version
- **Solution**: Use Gowin IDE v1.9.12 or later

**Timing Violations**:

- **Check**: SDC constraints loaded properly
- **Check**: Critical path in timing report
- **Solution**: Add pipeline registers if needed

**Clock Domain Crossing Warnings**:

- **Check**: Reset synchronization
- **Solution**: Verify all clock domains have proper reset

#### 4. **Advanced Debugging**

**Using Gowin Analyzer**:

```vhdl
-- Add these signals to Analyzer for debugging
signal pll_lock_stable  : std_logic;
signal hdmi_active      : std_logic;
signal current_pattern  : std_logic_vector(2 downto 0);
signal frame_counter    : unsigned(15 downto 0);
```

**Expected Signal Behavior**:

- `pll_lock_stable`: Should be high after ~50ms
- `hdmi_active`: High when display connected
- `current_pattern`: Should increment 0→1→2→3→4→5→0
- `frame_counter`: Should increment at ~60Hz

#### 5. **Hardware Validation**

**Check with Oscilloscope**:

- **27MHz Crystal**: Should see clean sine wave
- **HDMI Clock**: 126.000 MHz differential on pins 68/69
- **HDMI Data**: TMDS encoded data on pins 70/71, 72/73, 74/75

**Power Supply Check**:

- **3.3V Rail**: Should be stable ±5%
- **1.8V Rail**: Should be stable ±5%
- **Current Draw**: ~200-300mA typical

### Performance Validation

**Frame Rate Check**:

- LED 5 should blink at 30Hz (60Hz frame rate / 2)
- Pattern should change every 5.000 seconds exactly

**Timing Margins**:

- Setup slack: Should be >0.5ns
- Hold slack: Should be >0.1ns
- Check Place & Route timing report

### Support Resources

**Log Analysis**:

- Check synthesis log for warnings
- Review Place & Route timing report
- Monitor resource utilization

**Test Patterns**:

- Use manual pattern selection for specific tests
- Pattern 0: Basic color accuracy
- Pattern 1: Pixel sharpness
- Pattern 4: Motion smoothness

## Development Notes

### Recent Updates

- **Clock Naming Refactor**: All clock signals now use descriptive naming convention `clk_<frequency>_<purpose>` for better code clarity
- **Line Buffer Optimization**: Implemented Gowin_LBUF_SDPB IP cores for efficient ping-pong buffering
- **Proper CDC**: Added 2-stage synchronizers for reliable clock domain crossing

### Future Enhancements

- [ ] Higher resolutions (720p / 1080p)
- [ ] Richer HDMI audio (PCM samples, proper packet headers)
- [ ] Additional test patterns (SMPTE bars, zone plates)
- [ ] Variable refresh rates (30Hz, 75Hz)
- [ ] External video input / overlay pipeline

## License

Open source project - free to use and modify for your projects.

## Credits

- HDMI implementation for Tang Nano 9K
- TMDS encoding and timing generation
- Demo pattern generators and debug system
- Documentation and implementation guide

## Resources

- [Tang Nano 9K Documentation](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
- [Gowin IDE Download](https://www.gowinsemi.com/en/support/download_eda/)
- [HDMI 1.4 Specification](https://www.hdmi.org/)
- [TMDS Encoding Information](https://en.wikipedia.org/wiki/Transition-minimized_differential_signaling)

## Support

For issues, questions, or contributions, please open an issue on the project repository.

---

**TN9K HDMI** - Making HDMI output simple for Tang Nano 9K! 🚀
