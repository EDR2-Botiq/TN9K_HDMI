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
    -- Clock Frequencies (Hz) - 800x480@60Hz Configuration
    ----------------------------------------------------------------------------
    constant CRYSTAL_FREQ       : integer := 27000000;   -- 27 MHz crystal
    constant PIXEL_FREQ         : integer := 30000000;   -- 30 MHz pixel clock for 800x480@60Hz
    constant TMDS_FREQ          : integer := 150000000;  -- 150 MHz TMDS serial clock (5x pixel)
    constant AUDIO_SAMPLE_FREQ  : integer := 48000;      -- 48 kHz audio sample rate

    ----------------------------------------------------------------------------
    -- Video Timing Constants for 800x480@60Hz
    ----------------------------------------------------------------------------
    -- Based on common 800x480@60Hz timing (non-standard but widely supported)
    constant H_VISIBLE          : integer := 800;        -- Active horizontal pixels
    constant H_FRONT_PORCH      : integer := 40;         -- Horizontal front porch
    constant H_SYNC_WIDTH       : integer := 128;        -- Horizontal sync pulse width
    constant H_BACK_PORCH       : integer := 88;         -- Horizontal back porch
    constant H_TOTAL            : integer := 1056;       -- Total horizontal pixels

    constant V_VISIBLE          : integer := 480;        -- Active vertical lines
    constant V_FRONT_PORCH      : integer := 1;          -- Vertical front porch
    constant V_SYNC_WIDTH       : integer := 4;          -- Vertical sync pulse width
    constant V_BACK_PORCH       : integer := 23;         -- Vertical back porch
    constant V_TOTAL            : integer := 525;        -- Total vertical lines

    ----------------------------------------------------------------------------
    -- Audio Constants
    ----------------------------------------------------------------------------
    -- Audio sample rate divider for 30 MHz pixel clock
    -- Calculation: PIXEL_FREQ / (AUDIO_SAMPLE_FREQ * 2) = 30000000 / 96000 = 312.5
    constant AUDIO_DIV          : integer := 312;        -- Use 312 for ~48.08 kHz

    -- IEC 60958-3 sampling frequency code for 48 kHz
    constant SAMPLING_FREQ_CODE : std_logic_vector(3 downto 0) := "0010";

    ----------------------------------------------------------------------------
    -- HDMI Audio Clock Regeneration (ACR) Constants
    ----------------------------------------------------------------------------
    -- Standard ACR values for 48 kHz audio with 30 MHz pixel clock
    constant ACR_N_48KHZ        : integer := 6144;       -- Standard N for 48 kHz
    constant ACR_CTS_30MHZ      : integer := 30000;      -- CTS for 30 MHz (pixel_freq/1000)

    -- ACR values as 20-bit vectors
    constant ACR_N_VECTOR       : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(ACR_N_48KHZ, 20));
    constant ACR_CTS_VECTOR     : std_logic_vector(19 downto 0) := std_logic_vector(to_unsigned(ACR_CTS_30MHZ, 20));

    ----------------------------------------------------------------------------
    -- PLL Configuration Constants for 30MHz Pixel Clock
    ----------------------------------------------------------------------------
    -- Calculation: 27 MHz * 20 / 9 = 60 MHz base, then x2.5 = 150 MHz TMDS, /5 = 30 MHz pixel
    -- Alternative: 27 MHz * 50 / 9 = 150 MHz TMDS direct
    constant PLL_FBDIV          : integer := 49;         -- Feedback divider (value-1: 50-1=49)
    constant PLL_IDIV           : integer := 8;          -- Input divider (value-1: 9-1=8)
    constant PLL_ODIV           : integer := 4;          -- Output divider (VCO management)

    ----------------------------------------------------------------------------
    -- Timing Constants for Demo Pattern Generator
    ----------------------------------------------------------------------------
    constant CLOCKS_PER_SEC     : integer := PIXEL_FREQ;  -- Same as pixel frequency (30MHz)
    constant PATTERN_HOLD_TIME  : integer := 5;           -- Seconds per pattern
    constant PATTERN_COUNT      : integer := 6;           -- Number of test patterns

    ----------------------------------------------------------------------------
    -- Demo Tone Generator Constants
    ----------------------------------------------------------------------------
    constant DEMO_TONE_FREQ     : integer := 440;        -- 440 Hz A note
    constant SAMPLES_PER_TONE_CYCLE : integer := AUDIO_SAMPLE_FREQ / DEMO_TONE_FREQ;

end package hdmi_constants;

package body hdmi_constants is
    -- Package body can be empty since we only have constants
end package body hdmi_constants;