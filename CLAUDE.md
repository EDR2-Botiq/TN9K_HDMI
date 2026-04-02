# CLAUDE.md — TN9K_HDMI Codebase Guide

This file provides AI assistants with the context needed to work effectively in this repository.

---

## Project Overview

**Tang Nano 9K HDMI Transmitter** — A complete HDMI 1.4a video + audio output IP core for the
Tang Nano 9K FPGA board (GW1NR-9C, QN88 package). Outputs 800x480@60Hz with 6 auto-cycling
test patterns and 48kHz stereo audio.

- **Design languages**: VHDL 2008 (integration layer) + SystemVerilog 2017 (HDMI core)
- **Build tool**: Gowin EDA IDE v1.9.12+ (`gw_sh.exe` for CLI builds)
- **HDMI core**: Based on the open-source [hdl-util HDMI library](https://github.com/hdl-util/hdmi)
- **Primary branch**: `main`; feature work on `claude/...` branches

---

## Directory Structure

```
TN9K_HDMI/
├── src/
│   ├── TN9K_HDMI_800x480_top.vhd      # Top-level entity — integration of all components
│   ├── hdmi_constants.vhd             # SSOT for ALL timing/audio/PLL constants (edit here first)
│   ├── hdmi_package.vhd               # VHDL component declaration for hdmi.sv (SystemVerilog bridge)
│   ├── demo_pattern_gen.vhd           # 6-pattern video generator + 440Hz audio tone
│   ├── clocks/
│   │   ├── gowin_tmds_rpll.vhd        # PLL wrapper: 27MHz → 166.5MHz (TMDS clock)
│   │   ├── gowin_tmds_rpll.ipc        # Gowin IP configurator settings for PLL
│   │   ├── gowin_hdmi_clkdiv.vhd      # Clock divider wrapper: 166.5MHz → 33.3MHz (pixel clock)
│   │   └── gowin_hdmi_clkdiv.ipc      # Gowin IP configurator settings for divider
│   ├── hdmi/                          # SystemVerilog HDMI core (hdl-util library)
│   │   ├── hdmi.sv                    # Main HDMI controller (VIDEO_ID_CODE 200 = 800x480)
│   │   ├── packet_picker.sv           # Packet scheduler (video / audio / InfoFrames)
│   │   ├── packet_assembler.sv        # BCH error correction + packet assembly
│   │   ├── serializer.sv              # OSER10 serialization (10:1 DDR @ 166.5MHz)
│   │   ├── tmds_channel.sv            # TMDS 8b/10b encoding per RGB channel
│   │   ├── audio_sample_packet.sv     # IEC 60958-3 audio sample packets
│   │   ├── audio_clock_regeneration_packet.sv  # ACR N/CTS packets for 48kHz
│   │   ├── auxiliary_video_information_info_frame.sv  # AVI InfoFrame
│   │   ├── audio_info_frame.sv        # Audio InfoFrame
│   │   └── source_product_description_info_frame.sv   # SPD InfoFrame ("TangNano")
│   ├── tn9k_hdmi.cst                  # Pin constraints (IO_LOC + IO_PORT for all signals)
│   └── tn9k_hdmi.sdc                  # Timing constraints (27MHz input clock, false paths)
├── documents/
│   ├── HDMI_IMPLEMENTATION_GUIDE.md   # Architecture deep-dive
│   ├── BUILD.md                       # Detailed build/flash instructions
│   └── Tang_Nano_9K_Complete_Reference.md  # Hardware pinout & bank voltages
├── .claude/
│   └── commands/build-flash.md        # Custom /build-flash skill (Windows paths)
├── TN9K_HDMI_800x480.gprj            # Gowin IDE project file (XML)
├── build.tcl                          # CLI build script (opens .gprj)
├── build_mixed.tcl                    # CLI build script with explicit mixed-language settings
├── verify_hdmi.tcl                    # Post-build bitstream verification
├── README.md                          # User-facing documentation
└── BUILD.md                           # Top-level build quick-start
```

**Auto-generated (git-ignored)**: `impl/` — synthesis, P&R, bitstream outputs go here.

---

## Clock Architecture

The system uses a 3-stage clock hierarchy. All frequency values are authoritative from
`src/hdmi_constants.vhd`.

```
27MHz crystal (I_clk, Pin 52)
    │
    ▼ Gowin_TMDS_rPLL  (×37 ÷ 6 → actually ×50 ÷ 9 = 150MHz TMDS)
166.5MHz  (clk_tmds_166mhz)   — TMDS serial clock, feeds OSER10 serializers
    │
    ▼ Gowin_HDMI_CLKDIV (÷5)
33.3MHz   (clk_pixel_33mhz)   — Pixel clock, drives all VHDL logic
    │
    ▼ Audio divider process (÷694, toggle)
48kHz     (clk_audio)         — Audio sample clock → IEC 60958 packets
```

**Refresh rate**: 33.3MHz ÷ (1056 × 525) = **60.023Hz** (±0.04% error).

Key constants in `hdmi_constants.vhd`:
| Constant | Value | Purpose |
|---|---|---|
| `CRYSTAL_FREQ` | 27,000,000 | Input reference |
| `PIXEL_FREQ` | 30,000,000 | Nominal pixel clock (actual is 33.3MHz from PLL) |
| `TMDS_FREQ` | 150,000,000 | Nominal TMDS clock |
| `H_TOTAL` / `V_TOTAL` | 1056 / 525 | Full frame dimensions (including blanking) |
| `AUDIO_DIV` | 312 | Pixel-clock divider for audio tick |
| `ACR_N_48KHZ` | 6144 | HDMI ACR N value for 48kHz |
| `ACR_CTS_30MHZ` | 30000 | HDMI ACR CTS value |

---

## Single Source of Truth: `hdmi_constants.vhd`

**Always edit `src/hdmi_constants.vhd` first** when changing timing, frequency, or audio
parameters. Every other file (`demo_pattern_gen.vhd`, `TN9K_HDMI_800x480_top.vhd`) imports
`use work.hdmi_constants.all`. Do **not** hardcode magic numbers elsewhere.

---

## Top-Level Entity

**File**: `src/TN9K_HDMI_800x480_top.vhd`

```
entity TN9K_HDMI_800x480_top
  Ports:
    I_clk        in  std_logic          -- 27MHz crystal, Pin 52, Bank 1 (3.3V)
    I_rst_n      in  std_logic          -- Active-low reset, Pin 4, Bank 3 (1.8V)
    O_tmds_clk_p out std_logic          -- HDMI clock+, Pin 69
    O_tmds_clk_n out std_logic          -- HDMI clock-, Pin 68
    O_tmds_data_p out std_logic_vector(2 downto 0)  -- RGB TMDS data+, Pins 75/73/71
    O_tmds_data_n out std_logic_vector(2 downto 0)  -- RGB TMDS data-, Pins 74/72/70
    O_led_n      out std_logic_vector(5 downto 0)   -- Status LEDs, active-low
```

**Differential outputs are emulated** (not true LVDS): the `_n` signals are simply `not _p`.
This works on Tang Nano 9K because the HDMI pins are on Bank 1 (3.3V LVCMOS) and the board
schematic routes them to the HDMI connector accordingly.

**LED mapping** (all active-low — LED ON when signal is '0'):
| LED (`O_led_n` bit) | Signal | Meaning when ON |
|---|---|---|
| 0 | `not pll_locked` | PLL is locked |
| 1 | `not video_active` | Video is in active region |
| 2 | `not audio_enable` | Audio is enabled |
| 5:3 | `not current_pattern` | Current pattern number (binary, 0–5) |

---

## Mixed-Language Design

This project uses **VHDL wrapping SystemVerilog**. The bridge is `src/hdmi_package.vhd` which
declares the `hdmi` component with all generics and ports matching `src/hdmi/hdmi.sv`.

**Compilation order matters** (enforced in `build_mixed.tcl`):
1. SystemVerilog files in `src/hdmi/` first
2. VHDL files (`hdmi_constants`, `hdmi_package`, clocks, `demo_pattern_gen`, top-level) after

When adding new SystemVerilog modules, add them to the `src/hdmi/` directory and declare a
VHDL component wrapper in `hdmi_package.vhd` if they need to be instantiated from VHDL.

**Key generics for `hdmi` core** (set in `TN9K_HDMI_800x480_top.vhd`):
```vhdl
VIDEO_ID_CODE    => 200      -- Custom non-standard 800x480 mode
IT_CONTENT       => '1'
BIT_WIDTH        => 11       -- cx counter width
BIT_HEIGHT       => 10       -- cy counter width
DVI_OUTPUT       => '0'      -- Full HDMI (not DVI-only)
VIDEO_REFRESH_RATE => 60.0
AUDIO_RATE       => 48000
AUDIO_BIT_WIDTH  => 16
VENDOR_NAME      => x"54616E674E616E6F"   -- "TangNano"
PRODUCT_DESCRIPTION => x"465047412D44656D6F20202020202000"  -- "FPGA-Demo\0"
```

---

## Demo Pattern Generator

**File**: `src/demo_pattern_gen.vhd`

Generates 6 patterns with 5-second auto-cycling (controlled by `PATTERN_HOLD_TIME` and
`CLOCKS_PER_SEC` in `hdmi_constants.vhd`):

| Index | Pattern | Test purpose |
|---|---|---|
| 0 | Color Bars | Standard broadcast reference |
| 1 | Checkerboard | Pixel-level accuracy |
| 2 | RGB Gradient | Full color range |
| 3 | Grid/Crosshatch | Geometric accuracy |
| 4 | Moving Box | Motion/animation |
| 5 | Diagonal Rainbow Stripes | Color spectrum |

**Audio**: 440Hz square wave (A4 note) generated via a phase accumulator. Stereo, 16-bit,
48kHz, IEC 60958-3 compatible. Both left and right channels carry the same signal.

---

## Constraint Files

### Pin Constraints (`src/tn9k_hdmi.cst`)
Gowin CST format uses `IO_LOC` for pin placement and `IO_PORT` for electrical settings.
Bank 1 pins (HDMI, clock) use `LVCMOS33`; Bank 3 pins (reset, LEDs) use `LVCMOS18`.
The `CLOCK_LOC "I_clk" BUFG` directive ensures the crystal is routed through a global clock buffer.

### Timing Constraints (`src/tn9k_hdmi.sdc`)
- Input clock `clk_crystal` defined at 27MHz (period 37.037ns)
- HDMI TMDS outputs marked `set_false_path` (source-synchronous, self-timed)
- Reset marked `set_false_path` (asynchronous)
- Generated clocks (pixel, TMDS) are inferred automatically by Gowin tools

---

## Build Workflow

### Prerequisites
- Gowin EDA IDE v1.9.12 or later (`gw_sh.exe` on Windows)
- Tang Nano 9K board connected via USB
- Gowin Programmer (`programmer_cli.exe`)

### IDE Build (recommended)
1. Open `TN9K_HDMI_800x480.gprj` in Gowin IDE
2. Run Synthesis → Place & Route → Generate Bitstream
3. Bitstream output: `impl/pnr/TN9K_HDMI_800x480.fs`

### CLI Build (Windows)
```bat
cd E:\OneDrive\Desktop\FPGA\TN9K_HDMI
"C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" build.tcl
```
Or for explicit mixed-language settings:
```bat
"C:\Gowin\Gowin_V1.9.12_x64\IDE\bin\gw_sh.exe" build_mixed.tcl
```

### Claude Code Skill: `/build-flash`
The custom skill in `.claude/commands/build-flash.md` automates build + program in one command.
Usage: `/build-flash [sram|flash]` (defaults to `sram`).
- `sram` — volatile, lost on power cycle (use for testing)
- `flash` — permanent, survives power cycle

**Note**: The skill uses Windows paths (`E:\OneDrive\...`). Update `.claude/commands/build-flash.md`
if your local path differs.

### Expected Resource Usage
| Resource | Usage | Available | % |
|---|---|---|---|
| LUTs | ~3000 | 8640 | 35% |
| Registers | ~1200 | 8640 | 14% |
| PLLs | 2 | 2 | 100% |
| OSER10 | 4 | 4 | 100% |

---

## Key Development Conventions

### VHDL Style
- Use `use work.hdmi_constants.all` — never hardcode timing values
- Reset is active-high internally (`reset <= not I_rst_n or not pll_locked`)
- All synchronous logic clocked on `rising_edge(clk_pixel_33mhz)`
- Reset synchronizer uses 2-FF chain before feeding into `reset_n_sync`
- Signal naming: `_n` suffix = active-low, `_p`/`_n` pairs = differential

### SystemVerilog (HDMI core)
- The `src/hdmi/` files are from the hdl-util library — **prefer not modifying them**
- If changes are needed, note they diverge from upstream
- `VIDEO_ID_CODE 200` is a custom/non-standard extension for 800x480

### Constants
- All constants live in `src/hdmi_constants.vhd`
- The `PIXEL_FREQ` constant (30MHz) differs from the actual pixel clock (33.3MHz from PLL);
  this is a known naming artifact — the PLL is configured for 166.5MHz ÷ 5 = 33.3MHz

### Constraints
- Never change pin assignments without verifying against the Tang Nano 9K schematic
- Bank voltages are fixed by hardware: Bank 1 = 3.3V, Bank 3 = 1.8V
- Do not mix IO_TYPE standards within a bank

### Git
- Develop on the designated feature branch (`claude/add-claude-documentation-IW1Lr` or as specified)
- `impl/` is git-ignored; never commit build artifacts
- `*_tmp.vhd` files (auto-generated by Gowin IP) are git-ignored

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Check |
|---|---|---|
| No HDMI signal | PLL not locked (LED0 off) | Power supply, reset button |
| Garbled image | Wrong pixel clock frequency | `H_TOTAL`, `V_TOTAL` in constants |
| No audio | Audio packets disabled | `audio_enable` signal, `clk_audio` |
| Build fails — no OSER10 | Wrong device selected | Verify `GW1NR-9C` in project |
| Timing violations | SDC not loaded | Check `tn9k_hdmi.sdc` is in project |
| All LEDs off | Active-low confusion | LEDs ON = logic '0' on `O_led_n` |

---

## File Modification Guide

| Goal | Files to change |
|---|---|
| Change video timing | `hdmi_constants.vhd` (H_*/V_* constants) |
| Add/modify test pattern | `demo_pattern_gen.vhd` |
| Change audio frequency | `hdmi_constants.vhd` (`DEMO_TONE_FREQ`, `AUDIO_DIV`) |
| Change PLL frequency | `gowin_tmds_rpll.ipc` + `gowin_tmds_rpll.vhd` + update constants |
| Add a new top-level port | `TN9K_HDMI_800x480_top.vhd` + `tn9k_hdmi.cst` |
| Modify HDMI metadata | `TN9K_HDMI_800x480_top.vhd` (generic map for `hdmi` core) |
| Change LED behavior | `TN9K_HDMI_800x480_top.vhd` (LED assignments at bottom) |
