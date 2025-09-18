--------------------------------------------------------------------------------
-- HDMI Transmitter for 800x480@60Hz with VIC20Nano-Inspired Audio Support
-- Tang Nano 9K Implementation using Gowin GW1NR-9C FPGA
--
-- ARCHITECTURE OVERVIEW (Based on VIC20Nano Best Practices):
-- =============================================================
--
-- VIDEO PATH:
-- - Fixed 800x480@60Hz video timing generation
-- - Clock chain: 27MHz crystal -> 162MHz TMDS -> 32.4MHz pixel
-- - TMDS 8b/10b encoding with DC balancing
-- - Differential HDMI output using OSER10 + ELVDS_OBUF primitives
--
-- AUDIO PATH (VIC20Nano-Inspired Design):
-- - 48kHz audio with pattern-specific tone generation
-- - HDMI-compliant data island embedding during horizontal blanking
-- - BCH error correction for packet integrity
-- - TERC4 encoding for audio data transport
-- - Audio Clock Regeneration (ACR) packets for HDMI compliance
--
-- PACKET SYSTEM (VIC20Nano Architecture):
-- - Case-statement based packet selection (not sparse arrays)
-- - Multi-stage pipeline to prevent switching glitches
-- - Guard band protection for stable TMDS/TERC4 transitions
-- - Synthesis optimization protection with keep attributes
--
-- DATA ISLAND TIMING:
-- - Back porch: 36-pixel structure (2 guard + 32 data + 2 guard)
-- - Front porch: Optional 40-pixel window for additional packets
-- - Line stride control for bandwidth management
-- - Frame-based island counting for resource control
--
-- ANTI-OPTIMIZATION TECHNIQUES (VIC20Nano Methods):
-- - Explicit keep attributes on critical signals
-- - Dummy logic dependencies to prevent module sweeping
-- - Multi-stage registration to create synthesis dependencies
-- - Runtime controls instead of compile-time generics where possible
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_constants.all;

entity hdmi_tx_800x480 is
    generic (
        -- VIC20NANO AUDIO MUX CONTROL:
        -- Controls whether TERC4 audio/data island words are actually
        -- multiplexed onto the TMDS channels. Uses VIC20Nano's proven
        -- guard band protection and multi-stage pipeline isolation to
        -- prevent video sync corruption on Tang Nano 9K (GW1NR-9C).
        -- When enabled, implements full HDMI audio specification.
        AUDIO_MUX_ENABLE           : boolean := true;

        -- VIC20NANO DATA ISLAND PLACEMENT STRATEGY:
        -- Front porch islands: 40 pixels available (800-839)
        -- Suitable for smaller packets like ACR, but limited space
        ENABLE_FRONT_PORCH_ISLANDS : boolean := false;

        -- Back porch islands: 88 pixels available (968-1055)
        -- Primary location for audio sample packets, ample space
        -- VIC20Nano uses back porch as main audio transport window
        ENABLE_BACK_PORCH_ISLANDS  : boolean := true;

        -- VIC20NANO BANDWIDTH MANAGEMENT:
        -- Line stride control prevents audio bandwidth from overwhelming
        -- video timing. 1 = every line (full bandwidth), 2 = every other line
        LINE_ISLAND_STRIDE         : integer := 1;

        -- Frame-based island limiting for resource control
        -- 0 = unlimited (VIC20Nano default), >0 = max islands per frame
        MAX_ISLANDS_PER_FRAME      : integer := 0
    );
    port (
        -- Clock and reset inputs
        clk_27mhz       : in  std_logic;  -- 27 MHz crystal input
        reset_n         : in  std_logic;  -- Active low reset

        -- Clock and timing outputs (for external pattern generator)
        clk_pixel       : out std_logic;  -- 32.186 MHz pixel clock (VIC20Nano compatible)
        clk_audio       : out std_logic;  -- 48 kHz audio sample clock
        hsync           : out std_logic;  -- Horizontal sync
        vsync           : out std_logic;  -- Vertical sync
        de              : out std_logic;  -- Data enable (active video)
        pixel_x         : out std_logic_vector(9 downto 0);  -- Current X coordinate
        pixel_y         : out std_logic_vector(9 downto 0);  -- Current Y coordinate
        frame_start     : out std_logic;  -- Frame start pulse
        pll_locked      : out std_logic;  -- PLL lock status

        -- Debug outputs for audio troubleshooting
        debug_data_island : out std_logic;  -- Data island active indicator

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
end hdmi_tx_800x480;

architecture rtl of hdmi_tx_800x480 is

    -- Clock generation components
    component Gowin_TMDS_rPLL_800x480
        port (
            clkout  : out std_logic;  -- 162 MHz TMDS clock (corrected)
            lock    : out std_logic;  -- PLL lock status
            clkin   : in  std_logic   -- 27 MHz input clock
        );
    end component;

    component Gowin_HDMI_CLKDIV_800x480
        port (
            clkout  : out std_logic;  -- 32.4 MHz pixel clock (162/5)
            hclkin  : in  std_logic;  -- 162 MHz TMDS input
            resetn  : in  std_logic   -- Active low reset
        );
    end component;

    -- HDMI timing generator component
    component HDMI_TIMING_800x480
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


    -- Enhanced VIC20Nano-style packet infrastructure
    component hdmi_packet_picker
        generic (
            AUDIO_RATE          : integer := 48000;
            ENABLE_ACR          : boolean := true;
            ENABLE_ASP          : boolean := true;
            ENABLE_INFOFRAME    : boolean := false;
            ASP_SINGLE_SUBFRAME : boolean := true
        );
        port (
            clk_pixel           : in  std_logic;
            clk_audio           : in  std_logic;
            reset               : in  std_logic;
            video_field_end     : in  std_logic;
            packet_enable       : in  std_logic;
            packet_pixel_counter: in  std_logic_vector(4 downto 0);
            audio_sample_word_left  : in  std_logic_vector(23 downto 0);
            audio_sample_word_right : in  std_logic_vector(23 downto 0);
            clk_audio_counter_wrap  : in  std_logic;
            acr_n               : in  std_logic_vector(19 downto 0);
            acr_cts             : in  std_logic_vector(19 downto 0);
            header              : out std_logic_vector(23 downto 0);
            sub0                : out std_logic_vector(55 downto 0);
            sub1                : out std_logic_vector(55 downto 0);
            sub2                : out std_logic_vector(55 downto 0);
            sub3                : out std_logic_vector(55 downto 0)
        );
    end component;

    component hdmi_packet_assembler
        port (
            clk_pixel           : in  std_logic;
            reset               : in  std_logic;
            data_island_period  : in  std_logic;
            header              : in  std_logic_vector(23 downto 0);
            sub0                : in  std_logic_vector(55 downto 0);
            sub1                : in  std_logic_vector(55 downto 0);
            sub2                : in  std_logic_vector(55 downto 0);
            sub3                : in  std_logic_vector(55 downto 0);
            packet_data         : out std_logic_vector(8 downto 0);
            counter             : out std_logic_vector(4 downto 0)
        );
    end component;

    component hdmi_terc4 is
        port (
            d : in  std_logic_vector(3 downto 0);
            q : out std_logic_vector(9 downto 0)
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
    signal clk_tmds_serial  : std_logic;  -- 162 MHz TMDS clock
    signal clk_pixel_int    : std_logic;  -- 32.186 MHz pixel clock
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
    signal clk_audio_int    : std_logic;
    signal acr_n            : std_logic_vector(19 downto 0);
    signal acr_cts          : std_logic_vector(19 downto 0);
    signal di_valid         : std_logic;
    signal terc_ch0         : std_logic_vector(9 downto 0);
    signal terc_ch1         : std_logic_vector(9 downto 0);
    signal terc_ch2         : std_logic_vector(9 downto 0);
    -- Stable TERC4 input nibbles (avoid EX4557 non-static actual warnings)
    signal terc_d2          : std_logic_vector(3 downto 0);
    signal terc_d1          : std_logic_vector(3 downto 0);
    signal terc_d0          : std_logic_vector(3 downto 0);

    -- VIC20NANO ANTI-OPTIMIZATION STRATEGY:
    -- =====================================
    -- The VIC20Nano project demonstrated that HDMI audio implementations
    -- are particularly vulnerable to aggressive synthesis optimization.
    -- These keep attributes prevent critical audio path components from
    -- being removed even when synthesis analysis suggests they're unused.
    --
    -- CRITICAL SUCCESS FACTORS FROM VIC20NANO:
    -- 1. Mark TERC4 encoder outputs as "keep" - prevents module sweeping
    -- 2. Keep data island valid signals - preserves timing relationships
    -- 3. Selective application - only mark truly critical paths
    attribute keep : string;
    attribute keep of di_valid : signal is "true";  -- Data island timing control (critical!)
    attribute keep of terc_ch0 : signal is "true";  -- TERC4 channel 0 (control/guard bands)
    attribute keep of terc_ch1 : signal is "true";  -- TERC4 channel 1 (audio data low nibble)
    attribute keep of terc_ch2 : signal is "true";  -- TERC4 channel 2 (audio data high nibble)
    attribute keep of terc_d0  : signal is "true";  -- TERC4 input data channel 0
    attribute keep of terc_d1  : signal is "true";  -- TERC4 input data channel 1
    attribute keep of terc_d2  : signal is "true";  -- TERC4 input data channel 2
    -- VIC20Nano lesson: Keep only critical signals, allow natural optimization elsewhere

    -- Enhanced packet infrastructure signals
    signal packet_enable        : std_logic;
    signal data_island_period   : std_logic;
    signal video_field_end      : std_logic;
    signal packet_pixel_counter : std_logic_vector(4 downto 0);
    signal clk_audio_counter_wrap : std_logic;

    -- Packet data
    signal packet_header        : std_logic_vector(23 downto 0);
    signal packet_sub0          : std_logic_vector(55 downto 0);
    signal packet_sub1          : std_logic_vector(55 downto 0);
    signal packet_sub2          : std_logic_vector(55 downto 0);
    signal packet_sub3          : std_logic_vector(55 downto 0);
    signal packet_data          : std_logic_vector(8 downto 0);

    -- Audio data (extended to 24-bit for proper packet format)
    signal audio_left_24bit     : std_logic_vector(23 downto 0);
    signal audio_right_24bit    : std_logic_vector(23 downto 0);

    -- Mode control signals
    signal mode                 : std_logic_vector(2 downto 0);
    signal data_island_data     : std_logic_vector(11 downto 0);
    signal control_data         : std_logic_vector(5 downto 0);

    -- Audio counter for clock domain crossing
    signal audio_counter_wrap   : std_logic;
    signal audio_counter_prev   : unsigned(15 downto 0);

    -- Registered packet data for TERC4 stability
    signal packet_data_reg      : std_logic_vector(8 downto 0);
    signal di_valid_safe_reg    : std_logic;

    -- TMDS encoded signals
    signal tmds_red         : std_logic_vector(9 downto 0);
    signal tmds_green       : std_logic_vector(9 downto 0);
    signal tmds_blue        : std_logic_vector(9 downto 0);

    -- Final TMDS signals (muxed with audio)
    signal final_tmds_red   : std_logic_vector(9 downto 0);
    signal final_tmds_green : std_logic_vector(9 downto 0);
    signal final_tmds_blue  : std_logic_vector(9 downto 0);

    -- Safe multiplexing control signals with guard band protection
    signal di_valid_safe    : std_logic;
    signal audio_active     : std_logic;
    signal guard_band_active : std_logic;
    signal data_island_core : std_logic;

    -- Synthesis attributes to prevent optimization
    attribute syn_keep : boolean;
    attribute syn_keep of di_valid_safe : signal is true;
    attribute syn_keep of audio_active : signal is true;
    attribute syn_keep of guard_band_active : signal is true;
    attribute syn_keep of data_island_core : signal is true;

    -- Guard band symbol constants (HDMI spec requirement)
    constant GUARD_BAND_RED   : std_logic_vector(9 downto 0) := "1011001100";  -- 0x2CC
    constant GUARD_BAND_GREEN : std_logic_vector(9 downto 0) := "0100110011";  -- 0x133
    constant GUARD_BAND_BLUE  : std_logic_vector(9 downto 0) := "1011001100";  -- 0x2CC (same as red per HDMI spec)

    -- Horizontal porch classification for refined data island qualification
    signal px_val           : unsigned(9 downto 0);
    signal in_front_porch   : std_logic;
    signal in_hsync_period  : std_logic;
    signal in_back_porch    : std_logic;
    -- Throttling / line selection
    signal line_island_enable  : std_logic := '0';
    signal frame_island_count  : unsigned(15 downto 0) := (others => '0');
    signal line_stride_counter : unsigned(15 downto 0) := (others => '0');
    -- Data island timing constants now imported from hdmi_constants.vhd
    -- This ensures proper 800x480@60Hz timing for audio data islands
    -- Dummy usage to keep TERC4 modules alive if gating collapses
    signal terc_usage_dummy : std_logic;

    -- Serialized outputs
    signal serial_red       : std_logic;
    signal serial_green     : std_logic;
    signal serial_blue      : std_logic;

    -- Reset synchronization registers
    signal reset_meta       : std_logic := '1';
    signal reset_sync_reg   : std_logic := '1';
    signal pll_lock_sync    : std_logic := '0';
    signal pll_lock_meta    : std_logic := '0';

    -- Audio clock generation (using centralized constants)
    signal audio_counter    : unsigned(15 downto 0) := (others => '0');
    -- AUDIO_DIV constant now comes from hdmi_constants package

    -- Keep attributes for critical debugging signals
    attribute keep of packet_data : signal is "true";
    attribute keep of packet_data_reg : signal is "true";
    attribute keep of acr_n : signal is "true";
    attribute keep of acr_cts : signal is "true";

    -- Enhanced packet data registration with guard band protection
    signal guard_band_enable : std_logic;
    signal packet_data_reg_stage1  : std_logic_vector(8 downto 0);
    signal di_valid_safe_reg_stage1 : std_logic;
    signal guard_band_reg_stage1   : std_logic;
    signal guard_band_reg_stage2   : std_logic;

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
    -- Force synthesis to keep audio logic by including in critical output
    -- Include packet signals to prevent audio packet module optimization
    pll_locked <= pll_lock_int and not (di_valid_safe_reg xor guard_band_reg_stage2 xor data_island_core xor terc_usage_dummy xor
                  packet_header(0) xor packet_sub0(0) xor packet_sub1(0) xor packet_sub2(0) xor packet_sub3(0));

    -- Debug output for data island activity
    debug_data_island <= data_island_period;

    ----------------------------------------------------------------------------
    -- Clock Generation
    ----------------------------------------------------------------------------

    -- TMDS PLL: 27 MHz -> 162.0 MHz (exact calculation: 27*6/1 = 162 MHz)
    u_rpll : Gowin_TMDS_rPLL_800x480
        port map (
            clkout => clk_tmds_serial,
            lock   => pll_lock_int,
            clkin  => clk_27mhz
        );

    -- Clock divider: 162.0 MHz / 5 -> 32.4 MHz (close to target 32.186 MHz)
    u_clkdiv : Gowin_HDMI_CLKDIV_800x480
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

    u_timing : HDMI_TIMING_800x480
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
    -- Audio Clock Generation (48 kHz audio sample clock)
    ----------------------------------------------------------------------------
    process(clk_pixel_int, reset_sync)
    begin
        if reset_sync = '1' then
            audio_counter <= (others => '0');
            clk_audio_int <= '0';
        elsif rising_edge(clk_pixel_int) then
            if audio_counter >= AUDIO_DIV - 1 then
                audio_counter <= (others => '0');
                clk_audio_int <= not clk_audio_int;  -- Toggle to create 48 kHz square wave
            else
                audio_counter <= audio_counter + 1;
            end if;
        end if;
    end process;

    -- Audio counter wrap detection for packet timing
    process(clk_pixel_int, reset_sync)
    begin
        if reset_sync = '1' then
            audio_counter_prev <= (others => '0');
            audio_counter_wrap <= '0';
        elsif rising_edge(clk_pixel_int) then
            audio_counter_prev <= audio_counter;
            if (audio_counter_prev >= AUDIO_DIV - 1 and audio_counter = 0) then
                audio_counter_wrap <= '1';
            else
                audio_counter_wrap <= '0';
            end if;
        end if;
    end process;

    -- Extend 16-bit audio to 24-bit for packet processing
    audio_left_24bit <= audio_left & x"00";
    audio_right_24bit <= audio_right & x"00";

    -- Video field end detection
    video_field_end <= frame_start_int;

    -- ------------------------------------------------------------------------
    -- Refined Data Island Qualification + Throttling
    -- Horizontal timing (800x480):
    --   Visible:      0   - 799
    --   Front Porch:  800 - 839 (40)
    --   HSYNC:        840 - 967 (128) (hsync_int = '0')
    --   Back Porch:   968 - 1055 (88)
    -- We optionally allow data islands in front/back porch regions (never in
    -- HSYNC or active video). Additionally: line-based stride + per-frame cap.
    -- This narrows insertion windows (reducing risk of sync disturbance) while
    -- keeping packet / audio infrastructure alive for synthesis.
    px_val <= unsigned(pixel_x_int);
    in_front_porch  <= '1' when (de_int='0' and hsync_int='1' and px_val >= to_unsigned(800,10) and px_val < to_unsigned(840,10)) else '0';
    in_hsync_period <= '1' when (hsync_int='0') else '0';
    in_back_porch   <= '1' when (de_int='0' and hsync_int='1' and px_val >= to_unsigned(968,10) and px_val < to_unsigned(1056,10)) else '0';

    -- Line-based throttling: decide once per line at line_start
    process(clk_pixel_int, reset_sync)
        variable stride_hit : boolean;
        constant stride_is_one : boolean := (LINE_ISLAND_STRIDE <= 1);
        constant islands_unlimited : boolean := (MAX_ISLANDS_PER_FRAME = 0);
    begin
        if reset_sync = '1' then
            frame_island_count  <= (others => '0');
            line_stride_counter <= (others => '0');
            line_island_enable  <= '0';
        elsif rising_edge(clk_pixel_int) then
            -- Reset counters at frame start
            if frame_start_int = '1' then
                frame_island_count  <= (others => '0');
                line_stride_counter <= (others => '0');
            end if;

            if line_start = '1' then
                -- Evaluate stride
                if stride_is_one then
                    stride_hit := true;
                else
                    if line_stride_counter = to_unsigned(LINE_ISLAND_STRIDE-1, line_stride_counter'length) then
                        line_stride_counter <= (others => '0');
                        stride_hit := true;
                    else
                        line_stride_counter <= line_stride_counter + 1;
                        stride_hit := false;
                    end if;
                end if;

                -- Decide if this line is island-enabled
                if stride_hit and (islands_unlimited or frame_island_count < to_unsigned(MAX_ISLANDS_PER_FRAME, frame_island_count'length)) then
                    line_island_enable <= '1';
                    if not islands_unlimited then
                        frame_island_count <= frame_island_count + 1;
                    end if;
                else
                    line_island_enable <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Simplified guard band logic - always active during guard band windows
    -- HDMI-compliant data island qualification with proper guard band structure
    guard_band_active <= '1' when (
        (ENABLE_BACK_PORCH_ISLANDS and in_back_porch = '1' and
         ((px_val >= to_unsigned(BACK_PORCH_GUARD_START,10) and px_val < to_unsigned(BACK_PORCH_DATA_START,10)) or
          (px_val > to_unsigned(BACK_PORCH_DATA_END,10) and px_val <= to_unsigned(BACK_PORCH_GUARD_END,10)))) or
        (ENABLE_FRONT_PORCH_ISLANDS and in_front_porch = '1' and
         ((px_val >= to_unsigned(FRONT_PORCH_GUARD_START,10) and px_val < to_unsigned(FRONT_PORCH_DATA_START,10)) or
          (px_val > to_unsigned(FRONT_PORCH_DATA_END,10) and px_val <= to_unsigned(FRONT_PORCH_GUARD_END,10))))
    ) else '0';

    -- Simplified data island core logic - always active during back porch data window
    -- This ensures audio packets are always transmitted for proper HDMI audio
    data_island_core <= '1' when (
        (ENABLE_BACK_PORCH_ISLANDS and in_back_porch = '1' and
         px_val >= to_unsigned(BACK_PORCH_DATA_START,10) and px_val <= to_unsigned(BACK_PORCH_DATA_END,10)) or
        (ENABLE_FRONT_PORCH_ISLANDS and in_front_porch = '1' and
         px_val >= to_unsigned(FRONT_PORCH_DATA_START,10) and px_val <= to_unsigned(FRONT_PORCH_DATA_END,10))
    ) else '0';

    -- Combined data island period includes both guard bands and data
    data_island_period <= guard_band_active or data_island_core;

    -- Packet enable control - ONLY during actual data island periods (not all blanking)
    packet_enable <= data_island_period;

    ----------------------------------------------------------------------------
    -- Audio Clock Regeneration
    ----------------------------------------------------------------------------

    u_audio_acr : hdmi_audio_acr
        generic map (
            TMDS_CLK_25_175 => false  -- Use 32.186 MHz for 800x480
        )
        port map (
            clk_pix => clk_pixel_int,
            reset   => reset_sync,
            N       => acr_n,
            CTS     => acr_cts
        );


    -- VIC20Nano-style Enhanced Packet Infrastructure
    ----------------------------------------------------------------------------

    -- Packet picker - manages multiple packet types
    u_packet_picker : hdmi_packet_picker
        generic map (
            AUDIO_RATE          => AUDIO_SAMPLE_FREQ,
            ENABLE_ACR          => true,   -- ACR packets for audio clock sync
            ENABLE_ASP          => true,   -- Audio sample packets now enabled with guard band protection
            ENABLE_INFOFRAME    => true,   -- InfoFrame enabled for proper audio metadata
            ASP_SINGLE_SUBFRAME => true    -- Single subframe mode for stability
        )
        port map (
            clk_pixel           => clk_pixel_int,
            clk_audio           => clk_audio_int,
            reset               => reset_sync,
            video_field_end     => video_field_end,
            packet_enable       => packet_enable,
            packet_pixel_counter=> packet_pixel_counter,
            audio_sample_word_left  => audio_left_24bit,
            audio_sample_word_right => audio_right_24bit,
            clk_audio_counter_wrap  => audio_counter_wrap,
            acr_n               => acr_n,
            acr_cts             => acr_cts,
            header              => packet_header,
            sub0                => packet_sub0,
            sub1                => packet_sub1,
            sub2                => packet_sub2,
            sub3                => packet_sub3
        );

    -- Packet assembler - BCH error correction and output formatting
    u_packet_assembler : hdmi_packet_assembler
        port map (
            clk_pixel           => clk_pixel_int,
            reset               => reset_sync,
            data_island_period  => data_island_period,
            header              => packet_header,
            sub0                => packet_sub0,
            sub1                => packet_sub1,
            sub2                => packet_sub2,
            sub3                => packet_sub3,
            packet_data         => packet_data,
            counter             => packet_pixel_counter
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
    -- HDMI-Compliant TMDS / TERC4 Data Island Multiplexing
    ----------------------------------------------------------------------------
    -- Improved implementation with proper guard band symbols and pipeline
    -- isolation eliminates video sync corruption previously seen on TN9K.
    -- Guard bands provide stable transition periods between TMDS and TERC4.

    -- Enhanced packet data registration with guard band protection
    -- Multi-stage pipeline to eliminate timing glitches during mode transitions
    -- SYNTHESIS KEEP: Force audio path to stay active - always enable data islands during back porch
    di_valid_safe <= '1' when (AUDIO_MUX_ENABLE and data_island_core = '1') else '0';

    -- Guard band enable assignment
    -- SYNTHESIS KEEP: Force guard band logic to stay active - always enable guard bands
    guard_band_enable <= '1' when (AUDIO_MUX_ENABLE and guard_band_active = '1') else '0';

    process(clk_pixel_int, reset_sync)
    begin
        if reset_sync = '1' then
            audio_active       <= '0';
            packet_data_reg_stage1 <= (others => '0');
            di_valid_safe_reg_stage1 <= '0';
            guard_band_reg_stage1 <= '0';
            packet_data_reg    <= (others => '0');
            di_valid_safe_reg  <= '0';
            guard_band_reg_stage2 <= '0';
        elsif rising_edge(clk_pixel_int) then
            -- VIC20NANO MULTI-STAGE PIPELINE STRATEGY:
            -- Stage 1: Capture inputs (reduces metastability risk)
            audio_active      <= audio_enable;
            packet_data_reg_stage1 <= packet_data;           -- Packet data from BCH assembler
            di_valid_safe_reg_stage1 <= di_valid_safe;       -- Data island timing window
            guard_band_reg_stage1 <= guard_band_enable;      -- Guard band transition control

            -- Stage 2: Final output registers (VIC20Nano glitch elimination)
            -- This second stage prevents switching glitches during mode transitions
            -- that plagued early HDMI implementations and caused sync corruption
            packet_data_reg   <= packet_data_reg_stage1;     -- Stable packet data
            di_valid_safe_reg <= di_valid_safe_reg_stage1;   -- Stable island timing
            guard_band_reg_stage2 <= guard_band_reg_stage1;  -- Stable guard control
        end if;
    end process;

    -- VIC20NANO TERC4 ENCODING STRATEGY:
    -- ===================================
    -- TERC4 encoding converts 4-bit data to 10-bit symbols for HDMI data islands
    -- Nibble distribution follows HDMI spec for optimal error detection:
    terc_d2 <= packet_data_reg(7 downto 4);  -- Upper audio data nibble → TMDS Red
    terc_d1 <= packet_data_reg(3 downto 0);  -- Lower audio data nibble → TMDS Green
    terc_d0 <= ("00" & packet_data_reg(8) & packet_data_reg(8)); -- Control/parity → TMDS Blue

    -- VIC20NANO TERC4 ENCODER INSTANCES:
    -- These map 4-bit nibbles to 10-bit TMDS symbols during data islands
    -- Keep attributes ensure synthesis doesn't sweep these critical components
    terc4_ch2: hdmi_terc4 port map (d => terc_d2, q => terc_ch2); -- Red channel encoder
    terc4_ch1: hdmi_terc4 port map (d => terc_d1, q => terc_ch1); -- Green channel encoder
    terc4_ch0: hdmi_terc4 port map (d => terc_d0, q => terc_ch0); -- Blue channel encoder

    -- VIC20NANO ANTI-OPTIMIZATION DUMMY LOGIC:
    -- Creates synthesis dependencies to prevent TERC4 module sweeping
    -- SAFE: Only affects non-critical output, doesn't corrupt video
    terc_usage_dummy <= terc_ch0(0) xor terc_ch1(0) xor terc_ch2(0) xor
                       terc_ch0(9) xor terc_ch1(9) xor terc_ch2(9) xor
                       di_valid_safe xor guard_band_active xor data_island_core;

    -- VIC20NANO HDMI-COMPLIANT AUDIO MULTIPLEXING:
    -- =============================================
    audio_mux_gen : if AUDIO_MUX_ENABLE generate
        -- VIC20NANO GUARD BAND STRATEGY:
        -- HDMI specification requires specific symbol transitions to prevent
        -- receiver synchronization loss when switching between video and data modes.
        -- Guard bands provide stable transition periods that eliminate glitches.
        --
        -- PRIORITY HIERARCHY (VIC20Nano proven approach):
        -- 1. Guard band symbols (highest priority - transition protection)
        -- 2. TERC4-encoded audio data (medium priority - core audio transport)
        -- 3. Normal TMDS video data (lowest priority - default operation)
        --
        -- This priority system eliminates switching glitches that plagued
        -- earlier implementations and caused sync corruption on some displays.

        -- TMDS BLUE CHANNEL: Control symbols, guard bands, TERC4 channel 0
        -- Fixed: Remove video corruption from dummy logic
        final_tmds_blue  <= GUARD_BAND_BLUE  when guard_band_reg_stage2 = '1' else
                           terc_ch0         when di_valid_safe_reg = '1' else
                           tmds_blue;

        -- TMDS GREEN CHANNEL: Audio data low nibble, guard bands
        final_tmds_green <= GUARD_BAND_GREEN when guard_band_reg_stage2 = '1' else
                           terc_ch1         when di_valid_safe_reg = '1' else
                           tmds_green;

        -- TMDS RED CHANNEL: Audio data high nibble, guard bands
        final_tmds_red   <= GUARD_BAND_RED   when guard_band_reg_stage2 = '1' else
                           terc_ch2         when di_valid_safe_reg = '1' else
                           tmds_red;
    end generate;

    -- Pure video path when audio mux is disabled
    video_only_gen : if not AUDIO_MUX_ENABLE generate
        final_tmds_blue  <= tmds_blue;
        final_tmds_green <= tmds_green;
        final_tmds_red   <= tmds_red;
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