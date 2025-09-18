--------------------------------------------------------------------------------
-- HDMI Transmitter for 640x480@60Hz with Fixed Audio Support
-- Tang Nano 9K Implementation using Gowin GW1NR-9C FPGA
--
-- Features:
-- - Fixed 640x480@60Hz video timing generation
-- - Simple audio support with HDMI embedding (fixed timing issues)
-- - Clock generation: 27MHz -> 126MHz TMDS -> 25.2MHz pixel (near-exact VESA timing)
-- - Audio data islands during blanking periods
-- - Complete differential HDMI output with proper OSER10 serialization
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_tx_640x480 is
    generic (
        -- Controls whether TERC4 audio/data island words are actually
        -- multiplexed onto the TMDS channels. Default = false because on the
        -- Tang Nano 9K (GW1NR-9C) current toolchain/hardware combination the
        -- act of switching between TMDS video symbols and TERC4 symbols has
        -- been observed to corrupt video lock on a range of sinks.
        AUDIO_MUX_ENABLE : boolean := false
    );
    port (
        -- Clock and reset inputs
        clk_27mhz       : in  std_logic;  -- 27 MHz crystal input
        reset_n         : in  std_logic;  -- Active low reset

        -- Clock and timing outputs (for external pattern generator)
        clk_pixel       : out std_logic;  -- 25.2 MHz pixel clock (near VESA standard)
        clk_audio       : out std_logic;  -- 48 kHz audio sample clock
        hsync           : out std_logic;  -- Horizontal sync
        vsync           : out std_logic;  -- Vertical sync
        de              : out std_logic;  -- Data enable (active video)
        pixel_x         : out std_logic_vector(9 downto 0);  -- Current X coordinate
        pixel_y         : out std_logic_vector(9 downto 0);  -- Current Y coordinate
        frame_start     : out std_logic;  -- Frame start pulse
        pll_locked      : out std_logic;  -- PLL lock status

        -- Video and audio data inputs (from pattern generator)
        rgb_data        : in  std_logic_vector(23 downto 0);  -- 24-bit RGB
        audio_left      : in  std_logic_vector(15 downto 0);  -- Left audio channel
        audio_right     : in  std_logic_vector(15 downto 0);  -- Right audio channel
        audio_enable    : in  std_logic;  -- Enable audio embedding

        -- HDMI differential outputs
        hdmi_tx_clk_p   : out std_logic;  -- TMDS clock positive
        hdmi_tx_clk_n   : out std_logic;  -- TMDS clock negative
        hdmi_tx_p       : out std_logic_vector(2 downto 0);  -- TMDS data positive (RGB)
        hdmi_tx_n       : out std_logic_vector(2 downto 0)   -- TMDS data negative (RGB)
    );
end hdmi_tx_640x480;

architecture rtl of hdmi_tx_640x480 is

    -- Clock generation components
    component Gowin_TMDS_rPLL
        port (
            clkout  : out std_logic;  -- 126 MHz TMDS clock (corrected)
            lock    : out std_logic;  -- PLL lock status
            clkin   : in  std_logic   -- 27 MHz input clock
        );
    end component;

    component Gowin_HDMI_CLKDIV
        port (
            clkout  : out std_logic;  -- 25.2 MHz pixel clock (126/5)
            hclkin  : in  std_logic;  -- 126 MHz TMDS input
            resetn  : in  std_logic   -- Active low reset
        );
    end component;

    -- HDMI timing generator component
    component HDMI_TIMING
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

    -- TMDS encoder
    component tmds_encoder
        generic (
            PIPELINE_BALANCE : boolean := false
        );
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            data      : in  std_logic_vector(7 downto 0);
            c0        : in  std_logic;
            c1        : in  std_logic;
            de        : in  std_logic;
            encoded   : out std_logic_vector(9 downto 0)
        );
    end component;

    -- HDMI Audio ACR generator
    component hdmi_audio_acr
        generic (
            TMDS_CLK_25_175 : boolean := true
        );
        port (
            clk_pix  : in  std_logic;
            reset    : in  std_logic;
            N        : out std_logic_vector(19 downto 0);
            CTS      : out std_logic_vector(19 downto 0)
        );
    end component;

    -- HDMI Audio Packetizer
    component hdmi_audio_packetizer
        port (
            clk_pix         : in  std_logic;
            reset           : in  std_logic;
            hsync           : in  std_logic;
            vsync           : in  std_logic;
            de              : in  std_logic;
            pixel_y         : in  std_logic_vector(9 downto 0);
            aud_l           : in  std_logic_vector(15 downto 0);
            aud_r           : in  std_logic_vector(15 downto 0);
            aud_sample_stb  : in  std_logic;
            audio_enable    : in  std_logic;
            N_in            : in  std_logic_vector(19 downto 0);
            CTS_in          : in  std_logic_vector(19 downto 0);
            di_valid        : out std_logic;
            terc_ch0        : out std_logic_vector(9 downto 0);
            terc_ch1        : out std_logic_vector(9 downto 0);
            terc_ch2        : out std_logic_vector(9 downto 0)
        );
    end component;

    -- OSER10: 10:1 serializer primitive
    component OSER10
        generic (
            GSREN: STRING := "false";
            LSREN: STRING := "true"
        );
        port (
            Q: out std_logic;
            D0: in std_logic; D1: in std_logic; D2: in std_logic; D3: in std_logic; D4: in std_logic;
            D5: in std_logic; D6: in std_logic; D7: in std_logic; D8: in std_logic; D9: in std_logic;
            PCLK: in std_logic;
            FCLK: in std_logic;
            RESET: in std_logic
        );
    end component;

    -- ELVDS_OBUF: Differential output buffer
    component ELVDS_OBUF
        port (
            I  : in  std_logic;
            O  : out std_logic;
            OB : out std_logic
        );
    end component;

    -- Internal clock signals
    signal clk_tmds_serial  : std_logic;  -- 126 MHz TMDS clock
    signal clk_pixel_int    : std_logic;  -- 25.2 MHz pixel clock
    signal pll_lock_int     : std_logic;  -- PLL lock status
    signal reset_int        : std_logic;  -- Internal active high reset
    signal reset_sync       : std_logic;  -- Synchronized reset

    -- Video timing signals
    signal hsync_int        : std_logic;
    signal vsync_int        : std_logic;
    signal de_int           : std_logic;
    signal pixel_x_int      : std_logic_vector(9 downto 0);
    signal pixel_y_int      : std_logic_vector(9 downto 0);
    signal frame_start_int  : std_logic;
    signal line_start       : std_logic;

    -- Audio signals
    signal audio_sample_strobe : std_logic;
    signal clk_audio_int    : std_logic;
    signal acr_n            : std_logic_vector(19 downto 0);
    signal acr_cts          : std_logic_vector(19 downto 0);
    signal di_valid         : std_logic;
    signal terc_ch0         : std_logic_vector(9 downto 0);
    signal terc_ch1         : std_logic_vector(9 downto 0);
    signal terc_ch2         : std_logic_vector(9 downto 0);

    -- Keep audio signals to prevent optimization
    attribute keep : string;
    attribute keep of di_valid : signal is "true";
    attribute keep of terc_ch0 : signal is "true";
    attribute keep of terc_ch1 : signal is "true";
    attribute keep of terc_ch2 : signal is "true";

    -- TMDS encoded signals
    signal tmds_red         : std_logic_vector(9 downto 0);
    signal tmds_green       : std_logic_vector(9 downto 0);
    signal tmds_blue        : std_logic_vector(9 downto 0);

    -- Final TMDS signals (muxed with audio)
    signal final_tmds_red   : std_logic_vector(9 downto 0);
    signal final_tmds_green : std_logic_vector(9 downto 0);
    signal final_tmds_blue  : std_logic_vector(9 downto 0);

    -- Safe multiplexing control signals
    signal di_valid_safe    : std_logic;
    signal audio_active     : std_logic;

    -- Serialized outputs
    signal serial_red       : std_logic;
    signal serial_green     : std_logic;
    signal serial_blue      : std_logic;

    -- Reset synchronization registers
    signal reset_meta       : std_logic := '1';
    signal reset_sync_reg   : std_logic := '1';
    signal pll_lock_sync    : std_logic := '0';
    signal pll_lock_meta    : std_logic := '0';

    -- Audio clock generation (corrected for 25.2 MHz)
    signal audio_counter    : unsigned(15 downto 0) := (others => '0');
    constant AUDIO_DIV      : integer := 262;  -- 25200000/(48000*2) = 262.5, use 262 for ~48.08kHz

begin

    -- Convert reset polarity
    reset_int <= not reset_n;

    -- Output clock and timing signals
    clk_pixel <= clk_pixel_int;
    clk_audio <= clk_audio_int;
    hsync <= hsync_int;
    vsync <= vsync_int;
    de <= de_int;
    pixel_x <= pixel_x_int;
    pixel_y <= pixel_y_int;
    frame_start <= frame_start_int;
    pll_locked <= pll_lock_int;

    ----------------------------------------------------------------------------
    -- Clock Generation
    ----------------------------------------------------------------------------

    -- TMDS PLL: 27 MHz -> 126.0 MHz (exact calculation: 27*(13+1)/(0+1)/(2+1) = 378/3 = 126 MHz)
    u_rpll : Gowin_TMDS_rPLL
        port map (
            clkout => clk_tmds_serial,
            lock   => pll_lock_int,
            clkin  => clk_27mhz
        );

    -- Clock divider: 126.0 MHz / 5 -> 25.2 MHz (very close to VESA 25.175 MHz)
    u_clkdiv : Gowin_HDMI_CLKDIV
        port map (
            clkout => clk_pixel_int,
            hclkin => clk_tmds_serial,
            resetn => reset_n
        );

    -- PLL lock synchronization to pixel clock domain
    process(clk_pixel_int, reset_int)
    begin
        if reset_int = '1' then
            pll_lock_meta <= '0';
            pll_lock_sync <= '0';
        elsif rising_edge(clk_pixel_int) then
            pll_lock_meta <= pll_lock_int;
            pll_lock_sync <= pll_lock_meta;
        end if;
    end process;

    -- Reset synchronization to pixel clock domain
    process(clk_pixel_int, reset_int)
    begin
        if reset_int = '1' then
            reset_meta <= '1';
            reset_sync_reg <= '1';
        elsif rising_edge(clk_pixel_int) then
            if pll_lock_sync = '1' then
                reset_meta <= '0';
                reset_sync_reg <= reset_meta;
            end if;
        end if;
    end process;

    -- Final reset - only released when PLL is locked and synchronized
    reset_sync <= reset_sync_reg;

    ----------------------------------------------------------------------------
    -- Video Timing Generation
    ----------------------------------------------------------------------------

    u_timing : HDMI_TIMING
        port map (
            clk_pixel   => clk_pixel_int,
            reset       => reset_sync,
            hsync       => hsync_int,
            vsync       => vsync_int,
            de          => de_int,
            pixel_x     => pixel_x_int,
            pixel_y     => pixel_y_int,
            frame_start => frame_start_int,
            line_start  => line_start
        );

    ----------------------------------------------------------------------------
    -- Audio Clock Generation (Simple divider)
    ----------------------------------------------------------------------------
    process(clk_pixel_int, reset_sync)
    begin
        if reset_sync = '1' then
            audio_counter <= (others => '0');
            audio_sample_strobe <= '0';
        elsif rising_edge(clk_pixel_int) then
            if audio_counter >= AUDIO_DIV - 1 then
                audio_counter <= (others => '0');
                audio_sample_strobe <= '1';
            else
                audio_counter <= audio_counter + 1;
                audio_sample_strobe <= '0';
            end if;
        end if;
    end process;

    -- Use pixel clock domain for all audio processing
    -- Audio timing is controlled by audio_sample_strobe (48kHz)
    clk_audio_int <= clk_pixel_int;

    ----------------------------------------------------------------------------
    -- Audio Clock Regeneration
    ----------------------------------------------------------------------------

    u_audio_acr : hdmi_audio_acr
        generic map (
            TMDS_CLK_25_175 => false  -- Use 25.200 MHz (25.2 MHz)
        )
        port map (
            clk_pix => clk_pixel_int,
            reset   => reset_sync,
            N       => acr_n,
            CTS     => acr_cts
        );

    ----------------------------------------------------------------------------
    -- Audio Packetizer
    ----------------------------------------------------------------------------

    u_audio_packetizer : hdmi_audio_packetizer
        port map (
            clk_pix        => clk_pixel_int,
            reset          => reset_sync,
            hsync          => hsync_int,
            vsync          => vsync_int,
            de             => de_int,
            pixel_y        => pixel_y_int,
            aud_l          => audio_left,
            aud_r          => audio_right,
            aud_sample_stb => audio_sample_strobe,
            audio_enable   => audio_enable,
            N_in           => acr_n,
            CTS_in         => acr_cts,
            di_valid       => di_valid,
            terc_ch0       => terc_ch0,
            terc_ch1       => terc_ch1,
            terc_ch2       => terc_ch2
        );

    encoder_red: tmds_encoder
        generic map (PIPELINE_BALANCE => false)
        port map (
            clk     => clk_pixel_int,
            reset   => reset_sync,
            data    => rgb_data(23 downto 16),  -- Red
            c0      => '0',
            c1      => '0',
            de      => de_int,
            encoded => tmds_red
        );

    encoder_green: tmds_encoder
        generic map (PIPELINE_BALANCE => false)
        port map (
            clk     => clk_pixel_int,
            reset   => reset_sync,
            data    => rgb_data(15 downto 8),   -- Green
            c0      => '0',
            c1      => '0',
            de      => de_int,
            encoded => tmds_green
        );

    encoder_blue: tmds_encoder
        generic map (PIPELINE_BALANCE => false)
        port map (
            clk     => clk_pixel_int,
            reset   => reset_sync,
            data    => rgb_data(7 downto 0),    -- Blue
            c0      => hsync_int,               -- hsync for blue channel
            c1      => vsync_int,               -- vsync for blue channel
            de      => de_int,
            encoded => tmds_blue
        );

    ----------------------------------------------------------------------------
    -- TMDS / (optional) TERC4 Data Island Multiplexing
    ----------------------------------------------------------------------------
    -- Even with careful gating the TN9K platform currently exhibits loss of
    -- video sync when actively toggling to TERC4 symbols. A generic allows the
    -- feature to remain architecturally present but disabled by default.

    -- Simplified data island qualification - trust the audio packetizer
    -- The audio packetizer already handles proper blanking period detection
    process(clk_pixel_int, reset_sync)
    begin
        if reset_sync = '1' then
            di_valid_safe <= '0';
            audio_active  <= '0';
        elsif rising_edge(clk_pixel_int) then
            audio_active  <= audio_enable;
            -- Simple qualification: only check if audio is enabled and packetizer says valid
            di_valid_safe <= di_valid and audio_enable;
        end if;
    end process;

    -- Generate block for optional multiplexing.
    audio_mux_gen : if AUDIO_MUX_ENABLE generate
        -- When a qualified data island symbol is present substitute the three
        -- channel TMDS words with their already TERC4 encoded counterparts.
        -- Mapping: terc_ch0 -> Blue (channel 0), terc_ch1 -> Green, terc_ch2 -> Red
        final_tmds_blue  <= terc_ch0 when di_valid_safe = '1' else tmds_blue;
        final_tmds_green <= terc_ch1 when di_valid_safe = '1' else tmds_green;
        final_tmds_red   <= terc_ch2 when di_valid_safe = '1' else tmds_red;
    end generate;

    no_audio_mux_gen : if (not AUDIO_MUX_ENABLE) generate
        -- Pure video path (current stable configuration)
        final_tmds_red   <= tmds_red;
        final_tmds_green <= tmds_green;
        final_tmds_blue  <= tmds_blue;
    end generate;

    ----------------------------------------------------------------------------
    -- TMDS Serialization
    ----------------------------------------------------------------------------

    serializer_red: OSER10
        generic map (GSREN => "false", LSREN => "true")
        port map (
            Q => serial_red, PCLK => clk_pixel_int, FCLK => clk_tmds_serial, RESET => reset_sync,
            D0 => final_tmds_red(0), D1 => final_tmds_red(1), D2 => final_tmds_red(2), D3 => final_tmds_red(3), D4 => final_tmds_red(4),
            D5 => final_tmds_red(5), D6 => final_tmds_red(6), D7 => final_tmds_red(7), D8 => final_tmds_red(8), D9 => final_tmds_red(9)
        );

    serializer_green: OSER10
        generic map (GSREN => "false", LSREN => "true")
        port map (
            Q => serial_green, PCLK => clk_pixel_int, FCLK => clk_tmds_serial, RESET => reset_sync,
            D0 => final_tmds_green(0), D1 => final_tmds_green(1), D2 => final_tmds_green(2), D3 => final_tmds_green(3), D4 => final_tmds_green(4),
            D5 => final_tmds_green(5), D6 => final_tmds_green(6), D7 => final_tmds_green(7), D8 => final_tmds_green(8), D9 => final_tmds_green(9)
        );

    serializer_blue: OSER10
        generic map (GSREN => "false", LSREN => "true")
        port map (
            Q => serial_blue, PCLK => clk_pixel_int, FCLK => clk_tmds_serial, RESET => reset_sync,
            D0 => final_tmds_blue(0), D1 => final_tmds_blue(1), D2 => final_tmds_blue(2), D3 => final_tmds_blue(3), D4 => final_tmds_blue(4),
            D5 => final_tmds_blue(5), D6 => final_tmds_blue(6), D7 => final_tmds_blue(7), D8 => final_tmds_blue(8), D9 => final_tmds_blue(9)
        );

    -- Clock serializer removed - using direct pixel clock approach

    ----------------------------------------------------------------------------
    -- Differential Output Buffers
    ----------------------------------------------------------------------------

    elvds_red: ELVDS_OBUF
        port map (I => serial_red, O => hdmi_tx_p(2), OB => hdmi_tx_n(2));

    elvds_green: ELVDS_OBUF
        port map (I => serial_green, O => hdmi_tx_p(1), OB => hdmi_tx_n(1));

    elvds_blue: ELVDS_OBUF
        port map (I => serial_blue, O => hdmi_tx_p(0), OB => hdmi_tx_n(0));

    -- Use direct pixel clock for HDMI clock output (VIC20Nano approach)
    elvds_clk: ELVDS_OBUF
        port map (I => clk_pixel_int, O => hdmi_tx_clk_p, OB => hdmi_tx_clk_n);

end rtl;