-------------------------------------------------------------------------------
-- Tang Nano 9K Generic HDMI Display Controller with Demo Patterns
-- Supports 800x480@60Hz HDMI output with 6 auto-cycling test patterns
-- LEDs indicate current pattern number
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TN9K_HDMI_800x480_top is
    port(
        -- Clock and reset
        clk_crystal       : in    std_logic;  -- 27 MHz crystal input
        reset_n           : in    std_logic;  -- Reset (active low)

        -- Pattern selection inputs (optional, for manual override)
        pattern_select    : in    std_logic_vector(2 downto 0) := "000";  -- Manual pattern selection

        -- HDMI outputs
        hdmi_tx_clk_p     : out   std_logic;
        hdmi_tx_clk_n     : out   std_logic;
        hdmi_tx_p         : out   std_logic_vector(2 downto 0);  -- RGB channels
        hdmi_tx_n         : out   std_logic_vector(2 downto 0);

        -- Status LEDs (active low)
        led               : out   std_logic_vector(5 downto 0)
    );
end TN9K_HDMI_800x480_top;

architecture rtl of TN9K_HDMI_800x480_top is

    -- Self-contained HDMI TX module (with Audio)
    component hdmi_tx_800x480
        generic (
            AUDIO_MUX_ENABLE           : boolean := false;
            ENABLE_FRONT_PORCH_ISLANDS : boolean := false;
            ENABLE_BACK_PORCH_ISLANDS  : boolean := true;
            LINE_ISLAND_STRIDE         : integer := 1;
            MAX_ISLANDS_PER_FRAME      : integer := 0
        );
        port (
            -- Clock and reset inputs
            clk_27mhz       : in  std_logic;
            reset_n         : in  std_logic;

            -- Clock and timing outputs (for external pattern generator)
            clk_pixel       : out std_logic;
            clk_audio       : out std_logic;
            hsync           : out std_logic;
            vsync           : out std_logic;
            de              : out std_logic;
            pixel_x         : out std_logic_vector(9 downto 0);
            pixel_y         : out std_logic_vector(9 downto 0);
            frame_start     : out std_logic;
            pll_locked      : out std_logic;

            -- Debug outputs for audio troubleshooting
            debug_data_island : out std_logic;

            -- Video and audio data inputs (from pattern generator)
            rgb_data        : in  std_logic_vector(23 downto 0);
            audio_left      : in  std_logic_vector(15 downto 0);
            audio_right     : in  std_logic_vector(15 downto 0);
            audio_enable    : in  std_logic;

            -- HDMI differential outputs
            hdmi_tx_clk_p   : out std_logic;
            hdmi_tx_clk_n   : out std_logic;
            hdmi_tx_p       : out std_logic_vector(2 downto 0);
            hdmi_tx_n       : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Demo Pattern Generator (with Audio)
    component demo_pattern_gen
        port (
            -- Clock inputs (from HDMI TX module)
            clk_pixel       : in  std_logic;
            clk_audio       : in  std_logic;
            reset           : in  std_logic;

            -- Video timing inputs
            pixel_x         : in  std_logic_vector(9 downto 0);
            pixel_y         : in  std_logic_vector(9 downto 0);
            video_active    : in  std_logic;

            -- Pattern selection
            pattern_select  : in  std_logic_vector(2 downto 0);
            auto_mode       : in  std_logic;

            -- Audio control
            audio_enable_in : in  std_logic;

            -- Video output
            rgb_out         : out std_logic_vector(23 downto 0);

            -- Audio output
            audio_left      : out std_logic_vector(15 downto 0);
            audio_right     : out std_logic_vector(15 downto 0);
            audio_enable    : out std_logic;

            -- Status
            current_pattern : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Clock and timing signals from HDMI TX
    signal clk_pixel        : std_logic;  -- 25.175 MHz pixel clock
    signal clk_audio        : std_logic;  -- 48 kHz audio clock
    signal hsync            : std_logic;
    signal vsync            : std_logic;
    signal de               : std_logic;
    signal pixel_x          : std_logic_vector(9 downto 0);
    signal pixel_y          : std_logic_vector(9 downto 0);
    signal frame_start      : std_logic;
    signal pll_locked       : std_logic;  -- PLL lock status from HDMI TX

    -- Debug signals for audio troubleshooting
    signal debug_data_island : std_logic;

    -- Video data from pattern generator
    signal rgb_pattern      : std_logic_vector(23 downto 0);
    signal current_pattern  : std_logic_vector(2 downto 0);

    -- Audio data from pattern generator
    signal audio_left       : std_logic_vector(15 downto 0);
    signal audio_right      : std_logic_vector(15 downto 0);
    signal audio_enable_int : std_logic;  -- Internal audio enable from pattern gen

    -- Control signals
    signal reset            : std_logic;  -- Active high reset
    signal auto_mode        : std_logic;
    signal audio_enable     : std_logic;  -- Internal audio enable signal

    -- Debug and monitoring signals
    signal hdmi_active      : std_logic;  -- HDMI output is active
    signal frame_counter    : unsigned(15 downto 0) := (others => '0');
    signal audio_dependency : std_logic;  -- Audio-video dependency to prevent optimization
    signal rgb_pattern_adjusted : std_logic_vector(23 downto 0);  -- Audio-dependent video

begin

    -- Reset logic (active high internally)
    reset <= not reset_n;

    -- Control signals
    auto_mode <= '1';      -- Always enable auto-cycling
    audio_enable <= '1';   -- Always enable audio

    -- Create audio-video dependency to prevent synthesis optimization
    -- Use a safer approach that doesn't modify video data directly
    audio_dependency <= audio_left(0) xor audio_right(0) xor audio_enable_int;

    -- Pass video data unmodified to preserve sync integrity
    rgb_pattern_adjusted <= rgb_pattern;
    ----------------------------------------------------------------------------
    -- HDMI Activity Monitor - Simplified Logic
    ----------------------------------------------------------------------------
    -- Direct combinatorial logic to avoid clock domain issues
    hdmi_active <= pll_locked and de;

    -- Frame counter for LED blinking (only when system is active)
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            frame_counter <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Count frame starts for LED blinking
            if frame_start = '1' and pll_locked = '1' then
                frame_counter <= frame_counter + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Self-Contained HDMI Transmitter (with Audio)
    ----------------------------------------------------------------------------
    u_hdmi_tx : hdmi_tx_800x480
        generic map (
            -- FULL AUDIO ENABLED WITH SYNC CORRUPTION FIXES:
            AUDIO_MUX_ENABLE           => true,   -- Enable audio with fixed transitions
            ENABLE_FRONT_PORCH_ISLANDS => false,  -- VIC20Nano: Back porch only
            ENABLE_BACK_PORCH_ISLANDS  => true,   -- VIC20Nano: Primary audio window
            LINE_ISLAND_STRIDE         => 1,      -- Full bandwidth: Every line
            MAX_ISLANDS_PER_FRAME      => 0       -- Unlimited (bandwidth managed by content)
        )
        port map (
            -- Clock and reset inputs
            clk_27mhz       => clk_crystal,
            reset_n         => reset_n,

            -- Clock and timing outputs (to pattern generator)
            clk_pixel       => clk_pixel,
            clk_audio       => clk_audio,
            hsync           => hsync,
            vsync           => vsync,
            de              => de,
            pixel_x         => pixel_x,
            pixel_y         => pixel_y,
            frame_start     => frame_start,
            pll_locked      => pll_locked,

            -- Debug outputs
            debug_data_island => debug_data_island,

            -- Video and audio data input (with audio dependency)
            rgb_data        => rgb_pattern_adjusted,
            audio_left      => audio_left,
            audio_right     => audio_right,
            audio_enable    => audio_enable_int,

            -- HDMI differential outputs
            hdmi_tx_clk_p   => hdmi_tx_clk_p,
            hdmi_tx_clk_n   => hdmi_tx_clk_n,
            hdmi_tx_p       => hdmi_tx_p,
            hdmi_tx_n       => hdmi_tx_n
        );

    ----------------------------------------------------------------------------
    -- Demo Pattern Generator (with Audio)
    ----------------------------------------------------------------------------
    u_pattern_gen : demo_pattern_gen
        port map (
            -- Clock inputs (from HDMI TX module)
            clk_pixel       => clk_pixel,
            clk_audio       => clk_audio,
            reset           => reset,

            -- Video timing inputs
            pixel_x         => pixel_x,
            pixel_y         => pixel_y,
            video_active    => de,

            -- Pattern selection
            pattern_select  => pattern_select,
            auto_mode       => auto_mode,

            -- Audio control (always enabled)
            audio_enable_in => audio_enable,

            -- Video output
            rgb_out         => rgb_pattern,

            -- Audio output
            audio_left      => audio_left,
            audio_right     => audio_right,
            audio_enable    => audio_enable_int,

            -- Status
            current_pattern => current_pattern
        );

    ----------------------------------------------------------------------------
    -- LED Status Indicators (ACTIVE LOW - Tang Nano 9K hardware)
    ----------------------------------------------------------------------------
    -- LED 0: PLL Locked (ON when locked)
    led(0) <= not pll_locked;

    -- LED 1: HDMI Active (ON when generating active video)
    led(1) <= not hdmi_active;

    -- LED 2: Data Island Activity (ON when data islands are active)
    led(2) <= not debug_data_island;

    -- LED 3: Current pattern MSB (Pattern bit 2 - for patterns 4,5,6,7)
    led(3) <= not current_pattern(2);

    -- LED 4: Current pattern middle bit (Pattern bit 1 - for patterns 2,3,6,7)
    led(4) <= not current_pattern(1);

    -- LED 5: Current pattern LSB OR frame pulse (Pattern bit 0 OR 60Hz blink)
    led(5) <= not (current_pattern(0) or (frame_start and frame_counter(0)));

end rtl;