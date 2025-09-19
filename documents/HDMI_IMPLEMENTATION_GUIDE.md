# Tang Nano 9K HDMI Implementation Guide

## Overview

This guide covers the HDMI implementation for Tang Nano 9K FPGA producing 800x480@60Hz output with audio support using a mixed VHDL/SystemVerilog design.

## Key Implementation Details

### Clock Configuration
- **Input**: 27 MHz crystal
- **TMDS Clock**: 166.5 MHz (27 × 37 ÷ 6)
- **Pixel Clock**: 33.3 MHz (166.5 ÷ 5)
- **Refresh Rate**: 60.023 Hz (virtually perfect 60Hz)

### Pin Assignments (Tang Nano 9K)
```
// HDMI Differential Outputs
IO_LOC "O_tmds_clk_p" 69;        // HDMI Clock+
IO_LOC "O_tmds_clk_n" 68;        // HDMI Clock-
IO_LOC "O_tmds_data_p[2]" 75;    // Red+
IO_LOC "O_tmds_data_n[2]" 74;    // Red-
IO_LOC "O_tmds_data_p[1]" 73;    // Green+
IO_LOC "O_tmds_data_n[1]" 72;    // Green-
IO_LOC "O_tmds_data_p[0]" 71;    // Blue+
IO_LOC "O_tmds_data_n[0]" 70;    // Blue-

// Control and Status
IO_LOC "I_clk" 52;               // 27MHz Crystal
IO_LOC "I_rst_n" 4;              // Reset Button
IO_LOC "O_led_n[0]" 10;          // Status LEDs
IO_LOC "O_led_n[1]" 11;          // (Active Low)
IO_LOC "O_led_n[2]" 13;
IO_LOC "O_led_n[3]" 14;
IO_LOC "O_led_n[4]" 15;
IO_LOC "O_led_n[5]" 16;
```

### Bank Voltage Configuration
- **Bank 1**: 3.3V (HDMI pins, uses ELVDS_OBUF)
- **Bank 3**: 1.8V (LEDs, Reset)

### HDMI Pipeline Architecture

```
                    HDMI Signal Processing Pipeline
    ┌─────────────────────────────────────────────────────────────────────────┐
    │                          Clock Generation                               │
    │  27MHz ──► PLL ──► 166.5MHz ──► CLKDIV ──► 33.3MHz ──► Audio ──► 48kHz │
    │  Crystal   rPLL    TMDS Clock    /5        Pixel Clock   Divider        │
    └─────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
    ┌─────────────────┐    ┌──────────────────────────────────────────────────┐
    │ Pattern         │    │                HDMI Core (hdmi.sv)              │
    │ Generator       │───►│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
    │ (demo_pattern_  │    │  │   Timing    │  │   Packet    │  │   TMDS   │ │
    │  gen.vhd)       │    │  │  Generator  │  │   Picker    │  │ Encoder  │ │
    │                 │    │  │             │  │             │  │          │ │
    │ • Test Patterns │    │  │ • H/V Sync  │  │ • Video     │  │ • 8b/10b │ │
    │ • Audio Tones   │────┼─►│ • Blanking  │─►│ • Audio     │─►│ • RGB    │ │
    │ • Auto-Cycling  │    │  │ • Timing    │  │ • InfoFrame │  │ • Control│ │
    │                 │    │  │   Control   │  │ • ACR       │  │          │ │
    └─────────────────┘    │  └─────────────┘  └─────────────┘  └──────────┘ │
                           │                                                  │
                           │  ┌─────────────┐  ┌─────────────┐              │
                           │  │  Packet     │  │ Serializer  │              │
                           │  │ Assembler   │  │ (serializer │              │
                           │  │             │  │    .sv)     │              │
                           │  │ • BCH ECC   │  │             │              │
                           │  │ • Header    │─►│ • OSER10    │──────────────┼──┐
                           │  │ • Checksum  │  │ • 10:1 DDR  │              │  │
                           │  │             │  │ • 166.5MHz  │              │  │
                           │  └─────────────┘  └─────────────┘              │  │
                           └──────────────────────────────────────────────────┘  │
                                                                                  │
                                                                                  ▼
         ┌──────────────────────────────────────────────────────────────────────────┐
         │                      HDMI Physical Output                               │
         │                                                                          │
         │   TMDS_CLK ────► ELVDS_OBUF ────► Pin 69/68 ───► HDMI Clock±            │
         │   TMDS_R   ────► ELVDS_OBUF ────► Pin 75/74 ───► HDMI Red±              │
         │   TMDS_G   ────► ELVDS_OBUF ────► Pin 73/72 ───► HDMI Green±            │
         │   TMDS_B   ────► ELVDS_OBUF ────► Pin 71/70 ───► HDMI Blue±             │
         │                                                                          │
         └──────────────────────────────────────────────────────────────────────────┘
```

### Component Breakdown
1. **Pattern Generator** (`demo_pattern_gen.vhd`): Creates test patterns and audio
2. **HDMI Core** (`hdmi.sv`): SystemVerilog implementation with full HDMI 1.4a compliance
3. **Clock Generation**: Gowin PLL and divider IP cores
4. **Serialization**: OSER10 primitives for 10:1 TMDS serialization

### Video Timing (800x480@60Hz)
- **Active Area**: 800×480 pixels
- **Total Frame**: 1056×525 pixels
- **Horizontal**: 40px front porch, 128px sync, 88px back porch
- **Vertical**: 1 line front porch, 4 lines sync, 23 lines back porch

### Audio Support
- **Format**: 16-bit stereo PCM at 48kHz
- **Implementation**: IEC 60958 compliant audio packets
- **InfoFrames**: AVI, Audio, and SPD InfoFrames included
- **Clock Regeneration**: Automatic N/CTS packet generation

## Build Process

### Prerequisites
- Gowin EDA v1.9.12+ (mixed-language support required)
- Tang Nano 9K FPGA board
- 800x480 HDMI display

### Compilation Steps
1. **Open Project**: `TN9K_HDMI_800x480.gprj`
2. **Verify Files**: Ensure all VHDL and SystemVerilog files are included
3. **Build**: Run synthesis, place & route, and bitstream generation
4. **Program**: Use Gowin Programmer to load bitstream

### LED Status Indicators
- **LED 0**: PLL Lock Status (OFF = Locked)
- **LED 1**: Video Active (OFF = Active)
- **LED 2**: Audio Enable (OFF = Enabled)
- **LEDs 3-5**: Pattern Number (binary, changes every 5s)

## Troubleshooting

### No Display Output
- Check LED 0: Should be OFF (PLL locked)
- Verify HDMI cable connection
- Ensure display supports 800x480 resolution

### Wrong Colors/Patterns
- Check pin assignments in constraint file
- Verify TMDS channel mapping (R=2, G=1, B=0)
- Confirm clock frequencies are correct

### Audio Issues
- Check LED 2: Should be OFF (audio enabled)
- Verify display supports HDMI audio
- Ensure ACR packets are being generated

### Timing Issues
- Review timing report for setup/hold violations
- Check clock domain crossings
- Verify PLL lock stability

## Key Files
- `src/TN9K_HDMI_800x480_top.vhd`: Top-level VHDL entity
- `src/hdmi/hdmi.sv`: Main HDMI SystemVerilog core
- `src/demo_pattern_gen.vhd`: Pattern and audio generation
- `src/hdmi_constants.vhd`: Timing constants
- `tn9k_hdmi.cst`: Pin constraints
- `tn9k_hdmi.sdc`: Timing constraints

## Performance
- **Resource Usage**: ~3000 LUTs, ~1200 registers
- **Clock Performance**: 166.5 MHz TMDS, 33.3 MHz pixel
- **Timing Margin**: >0.5ns setup slack required
- **Display Compatibility**: Works with most 800x480 HDMI displays