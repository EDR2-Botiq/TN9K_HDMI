-------------------------------------------------------------------------------
-- Tang Nano 9K Generic HDMI Display Controller with Demo Patterns
-- Supports 640x480@60Hz HDMI output with 6 auto-cycling test patterns
-- LEDs indicate current pattern number
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity TN9K_HDMI_top is
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
end TN9K_HDMI_top;

architecture rtl of TN9K_HDMI_top is

    -- HDMI Encoder component
    component hdmi_encoder
        port (
            clk_25mhz_pixel  : in  std_logic;
            clk_125mhz_tmds  : in  std_logic;
            reset           : in  std_logic;
            rgb             : in  std_logic_vector(23 downto 0);
            hsync           : in  std_logic;
            vsync           : in  std_logic;
            de              : in  std_logic;
            hdmi_tx_clk_p   : out std_logic;
            hdmi_tx_clk_n   : out std_logic;
            hdmi_tx_p       : out std_logic_vector(2 downto 0);
            hdmi_tx_n       : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Demo Pattern Generator component
    component demo_pattern_gen
        port (
            clk_pixel       : in  std_logic;
            reset           : in  std_logic;
            pixel_x         : in  std_logic_vector(9 downto 0);
            pixel_y         : in  std_logic_vector(9 downto 0);
            video_active    : in  std_logic;
            pattern_select  : in  std_logic_vector(2 downto 0);
            auto_mode       : in  std_logic;
            pixel_counter   : in  unsigned(31 downto 0);
            rgb_out         : out std_logic_vector(23 downto 0);
            current_pattern : out std_logic_vector(2 downto 0)
        );
    end component;
    
    -- HDMI Timing Generator component
    component hdmi_timing
        port (
            clk_pixel    : in  std_logic;
            reset        : in  std_logic;
            hsync        : out std_logic;
            vsync        : out std_logic;
            de           : out std_logic;
            pixel_x      : out std_logic_vector(9 downto 0);
            pixel_y      : out std_logic_vector(9 downto 0);
            frame_start  : out std_logic;
            line_start   : out std_logic
        );
    end component;

    -- PLL component for TMDS clock generation
    component Gowin_TMDS_rPLL
        port (
            clkout  : out std_logic;  -- 125 MHz TMDS clock
            lock    : out std_logic;  -- PLL lock status
            clkin   : in  std_logic   -- 27 MHz input clock
        );
    end component;
    
    -- Clock divider component
    component Gowin_HDMI_CLKDIV
        port (
            clkout  : out std_logic;  -- 25 MHz pixel clock
            hclkin  : in  std_logic;  -- 125 MHz input
            resetn  : in  std_logic   -- Active low reset
        );
    end component;

    -- Internal signals
    signal clk_pixel        : std_logic;  -- 25 MHz HDMI pixel clock
    signal clk_tmds_serial  : std_logic;  -- 125 MHz TMDS serialization clock
    signal pll_lock         : std_logic;  -- PLL lock status
    signal reset            : std_logic;  -- Active high reset
    signal reset_sync       : std_logic;  -- Synchronized reset
    
    -- Video timing signals
    signal hsync            : std_logic;
    signal vsync            : std_logic;
    signal de               : std_logic;
    signal pixel_x          : std_logic_vector(9 downto 0);
    signal pixel_y          : std_logic_vector(9 downto 0);
    signal frame_start      : std_logic;
    signal line_start       : std_logic;
    
    -- Pattern generator signals
    signal rgb_pattern      : std_logic_vector(23 downto 0);
    signal current_pattern  : std_logic_vector(2 downto 0);
    signal auto_mode        : std_logic;
    
    -- Reset synchronization
    signal reset_meta       : std_logic;
    signal reset_sync_r     : std_logic;
    
    -- Debug and monitoring signals
    signal pll_lock_stable  : std_logic;  -- Stable PLL lock (debounced)
    signal pll_lock_counter : unsigned(19 downto 0) := (others => '0');
    signal hdmi_active      : std_logic;  -- HDMI output is active
    signal pixel_counter    : unsigned(31 downto 0) := (others => '0');
    signal frame_counter    : unsigned(15 downto 0) := (others => '0');

    -- Audio signals removed (not used in basic HDMI)
    signal hsync_counter    : unsigned(15 downto 0) := (others => '0');
    signal vsync_counter    : unsigned(15 downto 0) := (others => '0');
    
    -- Clock validation
    signal clk_pixel_valid  : std_logic;
    signal clk_tmds_valid   : std_logic;
    signal clock_valid      : std_logic;  -- Combined clock validation
    signal pixel_rate_ok    : std_logic;
    signal tmds_rate_ok     : std_logic;

begin

    -- Reset logic (active high internally)
    reset <= not reset_n;
    
    -- Force auto mode always enabled for testing
    auto_mode <= '1';  -- Always enable auto-cycling
    
    -- Reset synchronization to pixel clock domain
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            reset_meta <= '1';
            reset_sync_r <= '1';
            reset_sync <= '1';
        elsif rising_edge(clk_pixel) then
            reset_meta <= '0';
            reset_sync_r <= reset_meta;
            reset_sync <= reset_sync_r or not pll_lock_stable;
        end if;
    end process;
    
    ----------------------------------------------------------------------------
    -- Debug and Monitoring
    ----------------------------------------------------------------------------
    
    -- PLL Lock Debouncing (stable for ~40ms before considering locked)
    process(clk_crystal, reset)
    begin
        if reset = '1' then
            pll_lock_counter <= (others => '0');
            pll_lock_stable <= '0';
        elsif rising_edge(clk_crystal) then
            if pll_lock = '1' then
                if pll_lock_counter = 1048575 then  -- ~40ms @ 27MHz
                    pll_lock_stable <= '1';
                else
                    pll_lock_counter <= pll_lock_counter + 1;
                end if;
            else
                pll_lock_counter <= (others => '0');
                pll_lock_stable <= '0';
            end if;
        end if;
    end process;
    
    -- HDMI Activity Monitor (pixel counting)
    process(clk_pixel, reset_sync)
    begin
        if reset_sync = '1' then
            pixel_counter <= (others => '0');
            hdmi_active <= '0';
        elsif rising_edge(clk_pixel) then
            pixel_counter <= pixel_counter + 1;
            -- HDMI is active if we're generating pixels
            if de = '1' then
                hdmi_active <= '1';
            elsif pixel_counter(23 downto 0) = 0 then  -- Check every ~670ms
                hdmi_active <= '0';  -- Reset if no activity
            end if;
        end if;
    end process;
    
    -- Frame and Sync Pulse Counters for validation
    process(clk_pixel, reset_sync)
    begin
        if reset_sync = '1' then
            frame_counter <= (others => '0');
            hsync_counter <= (others => '0');
            vsync_counter <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Count frame starts (should be ~60Hz)
            if frame_start = '1' then
                frame_counter <= frame_counter + 1;
            end if;
            
            -- Count hsync pulses (should be ~31.5kHz)
            if hsync = '0' and hsync_counter(0) = '1' then  -- Falling edge
                hsync_counter <= hsync_counter + 1;
            end if;
            hsync_counter(0) <= hsync;
            
            -- Count vsync pulses (should be ~60Hz)
            if vsync = '0' and vsync_counter(0) = '1' then  -- Falling edge
                vsync_counter <= vsync_counter + 1;
            end if;
            vsync_counter(0) <= vsync;
        end if;
    end process;
    
    -- Clock Rate Validation (simplified)
    process(clk_pixel, reset_sync)
        variable pixel_rate_counter : unsigned(23 downto 0) := (others => '0');
    begin
        if reset_sync = '1' then
            pixel_rate_counter := (others => '0');
            pixel_rate_ok <= '0';
        elsif rising_edge(clk_pixel) then
            pixel_rate_counter := pixel_rate_counter + 1;
            -- Check if we're getting reasonable pixel rate (~25MHz)
            -- Counter should overflow every ~670ms at 25MHz
            if pixel_rate_counter = 0 then
                pixel_rate_ok <= '1';
            elsif pixel_rate_counter > 30000000 then  -- Too fast
                pixel_rate_ok <= '0';
            elsif pixel_rate_counter < 20000000 then  -- Too slow
                pixel_rate_ok <= '0';
            end if;
        end if;
    end process;
    
    -- Clock presence detection
    clk_pixel_valid <= '1' when pll_lock_stable = '1' and pixel_rate_ok = '1' else '0';
    clk_tmds_valid <= '1' when pll_lock_stable = '1' else '0';  -- Simplified
    clock_valid <= clk_pixel_valid and clk_tmds_valid;  -- Combined validation
    
    -- Overall TMDS rate OK (5:1 ratio maintained by hardware)
    tmds_rate_ok <= clk_pixel_valid and clk_tmds_valid;
    
    ----------------------------------------------------------------------------
    -- Clock Generation
    ----------------------------------------------------------------------------
    
    -- TMDS PLL: 27 MHz -> 125.875 MHz (exact rate for 640x480@60Hz)
    u_rpll : Gowin_TMDS_rPLL
        port map (
            clkout => clk_tmds_serial,
            lock   => pll_lock,
            clkin  => clk_crystal
        );
    
    -- Clock divider: 125.875 MHz / 5 -> 25.175 MHz pixel clock
    u_clkdiv : Gowin_HDMI_CLKDIV
        port map (
            clkout => clk_pixel,
            hclkin => clk_tmds_serial,
            resetn => reset_n
        );
    
    ----------------------------------------------------------------------------
    -- Video Timing Generator
    ----------------------------------------------------------------------------
    u_timing : hdmi_timing
        port map (
            clk_pixel   => clk_pixel,
            reset       => reset_sync,
            hsync       => hsync,
            vsync       => vsync,
            de          => de,
            pixel_x     => pixel_x,
            pixel_y     => pixel_y,
            frame_start => frame_start,
            line_start  => line_start
        );
    
    ----------------------------------------------------------------------------
    -- Demo Pattern Generator
    ----------------------------------------------------------------------------
    u_pattern_gen : demo_pattern_gen
        port map (
            clk_pixel       => clk_pixel,
            reset           => reset_sync,
            pixel_x         => pixel_x,
            pixel_y         => pixel_y,
            video_active    => de,
            pattern_select  => pattern_select,
            auto_mode       => auto_mode,
            pixel_counter   => pixel_counter,
            rgb_out         => rgb_pattern,
            current_pattern => current_pattern
        );

    -- Audio tone generator removed (not part of basic HDMI implementation)

    -- Audio monitoring removed

    ----------------------------------------------------------------------------
    -- HDMI Encoder
    ----------------------------------------------------------------------------
    u_hdmi : hdmi_encoder
        port map (
            clk_25mhz_pixel => clk_pixel,
            clk_125mhz_tmds => clk_tmds_serial,
            reset           => reset_sync,
            rgb             => rgb_pattern,
            hsync           => hsync,
            vsync           => vsync,
            de              => de,
            hdmi_tx_clk_p   => hdmi_tx_clk_p,
            hdmi_tx_clk_n   => hdmi_tx_clk_n,
            hdmi_tx_p       => hdmi_tx_p,
            hdmi_tx_n       => hdmi_tx_n
        );
    
    ----------------------------------------------------------------------------
    -- LED Status Indicators (active low) - Comprehensive Debug Display
    ----------------------------------------------------------------------------
    -- LED 0: PLL Stable Lock (ON when stable and locked)
    led(0) <= not pll_lock_stable;
    
    -- LED 1: HDMI Active (ON when generating active video)
    led(1) <= not hdmi_active;
    
    -- LED 2: Clock validation (ON when clocks are valid)
    led(2) <= not clock_valid;
    
    -- LED 3: Current pattern MSB (Pattern bit 2 - for patterns 4,5,6,7)
    led(3) <= not current_pattern(2);
    
    -- LED 4: Current pattern middle bit (Pattern bit 1 - for patterns 2,3,6,7)
    led(4) <= not current_pattern(1);
    
    -- LED 5: Current pattern LSB OR frame pulse (Pattern bit 0 OR 60Hz blink)
    led(5) <= not (current_pattern(0) or (frame_start and frame_counter(0)));

end rtl;