-------------------------------------------------------------------------------
-- hdmi_constants.vhd
-- Centralized constants for HDMI system - Single Source of Truth (SSOT)
-- All timing and audio parameters defined here to avoid duplication
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package hdmi_constants is

    ----------------------------------------------------------------------------
    -- Clock Frequencies (Hz)
    ----------------------------------------------------------------------------
    constant CRYSTAL_FREQ       : integer := 27000000;   -- 27 MHz crystal
    constant TMDS_FREQ          : integer := 162000000;  -- 162 MHz TMDS serial clock (27*6=162MHz)
    constant PIXEL_FREQ         : integer := 32400000;   -- 32.4 MHz GENERATED pixel clock (162MHz/5)
    constant AUDIO_SAMPLE_FREQ  : integer := 48000;      -- 48 kHz audio sample rate

    ----------------------------------------------------------------------------
    -- Audio Constants
    ----------------------------------------------------------------------------
    -- Audio sample rate divider for 32.4 MHz pixel clock (162MHz/5)
    -- Calculation: 32400000 / (48000 * 2) = 337.5, rounded to 338 for closer to 48 kHz
    constant AUDIO_DIV          : integer := 338;        -- Use 338 for ~47.93 kHz (closer to 48 kHz target)

    -- IEC 60958-3 sampling frequency code for 48 kHz
    constant SAMPLING_FREQ_CODE : std_logic_vector(3 downto 0) := "0010";

    ----------------------------------------------------------------------------
    -- HDMI Audio Clock Regeneration (ACR) Constants - VIC20Nano Compatible
    ----------------------------------------------------------------------------
    -- ACR values for 48 kHz audio with GENERATED 32.4 MHz pixel clock
    -- Generated pixel clock: 162 MHz ÷ 5 = 32.4 MHz (from PLL + CLKDIV)
    constant ACR_N_48KHZ        : integer := 6144;       -- Standard N for 48 kHz (HDMI specification)
    constant ACR_CTS_32_4MHZ    : integer := 32400;      -- CTS for GENERATED 32.4 MHz pixel clock

    -- ACR values as 20-bit vectors
    constant ACR_N_VECTOR       : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(ACR_N_48KHZ, 20));
    constant ACR_CTS_VECTOR     : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(ACR_CTS_32_4MHZ, 20));

    ----------------------------------------------------------------------------
    -- PLL Configuration Constants (800x480@60Hz)
    ----------------------------------------------------------------------------
    -- Formula: CLKOUT = 27 MHz × (FBDIV_SEL + 1) ÷ (IDIV_SEL + 1)
    -- Target: 162 MHz TMDS clock = 27 × 6 ÷ 1 = 162 MHz
    constant PLL_FBDIV          : integer := 5;          -- Feedback divider (FBDIV_SEL = 5, actual = 6)
    constant PLL_IDIV           : integer := 0;          -- Input divider (IDIV_SEL = 0, actual = 1)
    constant PLL_ODIV           : integer := 4;          -- Output divider (VCO management)

    ----------------------------------------------------------------------------
    -- Timing Constants for Demo Pattern Generator
    ----------------------------------------------------------------------------
    constant CLOCKS_PER_SEC     : integer := PIXEL_FREQ;  -- Same as pixel frequency
    constant PATTERN_HOLD_TIME  : integer := 5;           -- Seconds per pattern
    constant PATTERN_COUNT      : integer := 6;           -- Number of test patterns

    ----------------------------------------------------------------------------
    -- Demo Tone Generator Constants
    ----------------------------------------------------------------------------
    constant DEMO_TONE_FREQ     : integer := 440;        -- 440 Hz A note
    constant SAMPLES_PER_TONE_CYCLE : integer := AUDIO_SAMPLE_FREQ / DEMO_TONE_FREQ;

    ----------------------------------------------------------------------------
    -- HDMI Data Island Timing Constants (800x480@60Hz) - VIC20Nano Compatible
    ----------------------------------------------------------------------------
    -- Back porch data island placement: HDMI-compliant timing for reliable audio
    -- Horizontal timing: Back porch is pixels 968-1055 (88 pixels available)
    -- HDMI Standard: 2px guard + 32px data + 2px guard = 36px total (VIC20Nano proven)
    constant BACK_PORCH_GUARD_START : integer := 970;   -- Start early in back porch for maximum compatibility
    constant BACK_PORCH_DATA_START  : integer := 972;   -- Start of data island core (2px guard band)
    constant BACK_PORCH_DATA_END    : integer := 1003;  -- End of data island core (32px full packet data)
    constant BACK_PORCH_GUARD_END   : integer := 1005;  -- End of trailing guard band (total 36px structure)

    -- Front porch data island placement: pixels 800-839 (40 total pixels)
    -- Sufficient space for full 36-pixel structure
    constant FRONT_PORCH_GUARD_START : integer := 802;  -- Start of leading guard band
    constant FRONT_PORCH_DATA_START  : integer := 804;  -- Start of data island core
    constant FRONT_PORCH_DATA_END    : integer := 835;  -- End of data island core (32 pixels)
    constant FRONT_PORCH_GUARD_END   : integer := 837;  -- End of trailing guard band

end package hdmi_constants;

package body hdmi_constants is
    -- Package body can be empty since we only have constants
end package body hdmi_constants;