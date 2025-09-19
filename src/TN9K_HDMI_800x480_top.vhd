-------------------------------------------------------------------------------
-- Tang Nano 9K HDMI Display Controller with VIC20Nano hdl-util HDMI Core
-- Supports 800x480@60Hz HDMI output with 6 auto-cycling test patterns
-- Uses proven hdl-util HDMI implementation for standards compliance
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_constants.all;

entity TN9K_HDMI_800x480_top is
    port(
        -- Clock and reset
        I_clk             : in    std_logic;  -- 27 MHz crystal input
        I_rst_n           : in    std_logic;  -- Reset (active low)

        -- HDMI outputs (differential)
        O_tmds_clk_p      : out   std_logic;
        O_tmds_clk_n      : out   std_logic;
        O_tmds_data_p     : out   std_logic_vector(2 downto 0);  -- RGB channels
        O_tmds_data_n     : out   std_logic_vector(2 downto 0);

        -- Status LEDs (active low)
        O_led_n           : out   std_logic_vector(5 downto 0)
    );
end TN9K_HDMI_800x480_top;

architecture rtl of TN9K_HDMI_800x480_top is

    -- Clock generation components
    component Gowin_TMDS_rPLL is
        port (
            clkout: out std_logic;
            lock: out std_logic;
            clkin: in std_logic
        );
    end component;

    component Gowin_HDMI_CLKDIV is
        port (
            clkout: out std_logic;
            hclkin: in std_logic;
            resetn: in std_logic
        );
    end component;

    -- Demo Pattern Generator
    component demo_pattern_gen
        port (
            clk_pixel       : in  std_logic;
            clk_audio       : in  std_logic;
            reset           : in  std_logic;
            pixel_x         : in  std_logic_vector(9 downto 0);
            pixel_y         : in  std_logic_vector(9 downto 0);
            video_active    : in  std_logic;
            pattern_select  : in  std_logic_vector(2 downto 0);
            auto_mode       : in  std_logic;
            audio_enable_in : in  std_logic;
            rgb_out         : out std_logic_vector(23 downto 0);
            audio_left      : out std_logic_vector(15 downto 0);
            audio_right     : out std_logic_vector(15 downto 0);
            audio_enable    : out std_logic;
            current_pattern : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Clock signals
    signal clk_tmds_166mhz : std_logic;
    signal clk_pixel_33mhz : std_logic;
    signal pll_locked      : std_logic;
    signal reset_n_sync    : std_logic;
    signal reset           : std_logic;

    -- Video timing and control signals
    signal cx, cy          : std_logic_vector(10 downto 0);
    signal video_active    : std_logic;
    signal pixel_x         : std_logic_vector(9 downto 0);
    signal pixel_y         : std_logic_vector(9 downto 0);

    -- Pattern generator signals
    signal rgb_data        : std_logic_vector(23 downto 0);
    signal audio_left      : std_logic_vector(15 downto 0);
    signal audio_right     : std_logic_vector(15 downto 0);
    signal audio_enable    : std_logic;
    signal current_pattern : std_logic_vector(2 downto 0);

    -- HDMI core signals (converted from std_logic_vector to logic arrays)
    signal tmds_p_internal : std_logic_vector(2 downto 0);
    signal tmds_n_internal : std_logic_vector(2 downto 0);

    -- Audio clock generation
    signal audio_clk_counter : unsigned(8 downto 0) := (others => '0');
    signal clk_audio         : std_logic := '0';

    -- Reset synchronizer
    signal reset_sync_ff     : std_logic_vector(1 downto 0) := "00";

begin

    -- Reset logic
    reset <= not I_rst_n or not pll_locked;

    -- Reset synchronizer for pixel clock domain
    process(clk_pixel_33mhz, reset)
    begin
        if reset = '1' then
            reset_sync_ff <= "00";
        elsif rising_edge(clk_pixel_33mhz) then
            reset_sync_ff <= reset_sync_ff(0) & '1';
        end if;
    end process;
    reset_n_sync <= reset_sync_ff(1);

    -- Clock generation: 27MHz -> 166.5MHz TMDS -> 33.3MHz pixel
    pll_tmds_inst : Gowin_TMDS_rPLL
        port map (
            clkout => clk_tmds_166mhz,
            lock   => pll_locked,
            clkin  => I_clk
        );

    clkdiv_inst : Gowin_HDMI_CLKDIV
        port map (
            clkout  => clk_pixel_33mhz,
            hclkin  => clk_tmds_166mhz,
            resetn  => reset_n_sync
        );

    -- Audio clock generation (33.3MHz / 694 ≈ 48kHz)
    process(clk_pixel_33mhz)
    begin
        if rising_edge(clk_pixel_33mhz) then
            if reset = '1' then
                audio_clk_counter <= (others => '0');
                clk_audio <= '0';
            else
                if audio_clk_counter = 346 then  -- 33.3MHz / 694 / 2 ≈ 24kHz toggle = 48kHz effective
                    audio_clk_counter <= (others => '0');
                    clk_audio <= not clk_audio;
                else
                    audio_clk_counter <= audio_clk_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Video timing generation (800x480@60Hz)
    process(clk_pixel_33mhz)
        variable h_count : integer range 0 to H_TOTAL-1 := 0;
        variable v_count : integer range 0 to V_TOTAL-1 := 0;
    begin
        if rising_edge(clk_pixel_33mhz) then
            if reset = '1' then
                h_count := 0;
                v_count := 0;
            else
                -- Horizontal counter
                if h_count = H_TOTAL-1 then
                    h_count := 0;
                    -- Vertical counter
                    if v_count = V_TOTAL-1 then
                        v_count := 0;
                    else
                        v_count := v_count + 1;
                    end if;
                else
                    h_count := h_count + 1;
                end if;

                -- Convert to std_logic_vector for outputs
                cx <= std_logic_vector(to_unsigned(h_count, 11));
                cy <= std_logic_vector(to_unsigned(v_count, 11));
            end if;
        end if;
    end process;

    -- Video active and pixel coordinate generation
    video_active <= '1' when unsigned(cx) < H_VISIBLE and unsigned(cy) < V_VISIBLE else '0';
    pixel_x <= cx(9 downto 0) when unsigned(cx) < H_VISIBLE else (others => '0');
    pixel_y <= cy(9 downto 0) when unsigned(cy) < V_VISIBLE else (others => '0');

    -- Demo Pattern Generator
    pattern_gen_inst : demo_pattern_gen
        port map (
            clk_pixel       => clk_pixel_33mhz,
            clk_audio       => clk_audio,
            reset           => reset,
            pixel_x         => pixel_x,
            pixel_y         => pixel_y,
            video_active    => video_active,
            pattern_select  => "000",  -- Auto mode
            auto_mode       => '1',
            audio_enable_in => '1',
            rgb_out         => rgb_data,
            audio_left      => audio_left,
            audio_right     => audio_right,
            audio_enable    => audio_enable,
            current_pattern => current_pattern
        );

    -- HDMI Core (hdl-util SystemVerilog implementation)
    -- Component declaration for mixed-language design
    component hdmi
        generic (
            VIDEO_ID_CODE : integer := 0;
            AUDIO_RATE : integer := 48000;
            AUDIO_BIT_WIDTH : integer := 16;
            VENDOR_NAME : string := "TangNano";
            PRODUCT_DESCRIPTION : string := "FPGA-Demo "
        );
        port (
            clk_pixel_x5 : in std_logic;
            clk_pixel : in std_logic;
            clk_audio : in std_logic;
            reset : in std_logic;
            rgb : in std_logic_vector(23 downto 0);
            audio_sample_word_left : in std_logic_vector(15 downto 0);
            audio_sample_word_right : in std_logic_vector(15 downto 0);
            audio_enable : in std_logic;
            external_sync_enable : in std_logic;
            external_hsync : in std_logic;
            external_vsync : in std_logic;
            external_de : in std_logic;
            tmds_p : out std_logic_vector(2 downto 0);
            tmds_n : out std_logic_vector(2 downto 0);
            tmds_clock_p : out std_logic;
            tmds_clock_n : out std_logic;
            cx : out std_logic_vector(10 downto 0);
            cy : out std_logic_vector(10 downto 0);
            screen_start_x : out std_logic_vector(10 downto 0);
            screen_start_y : out std_logic_vector(10 downto 0);
            screen_width : out std_logic_vector(10 downto 0);
            screen_height : out std_logic_vector(10 downto 0)
        );
    end component;

    hdmi_core_inst : hdmi
        generic map (
            VIDEO_ID_CODE => 0,
            AUDIO_RATE => 48000,
            AUDIO_BIT_WIDTH => 16,
            VENDOR_NAME => "TangNano",
            PRODUCT_DESCRIPTION => "FPGA-Demo "
        )
        port map (
            clk_pixel_x5 => clk_tmds_166mhz,
            clk_pixel => clk_pixel_33mhz,
            clk_audio => clk_audio,
            reset => reset,
            rgb => rgb_data,
            audio_sample_word_left => audio_left,
            audio_sample_word_right => audio_right,
            audio_enable => audio_enable,
            external_sync_enable => '0',
            external_hsync => '0',
            external_vsync => '0',
            external_de => '0',
            tmds_p => tmds_p_internal,
            tmds_n => tmds_n_internal,
            tmds_clock_p => O_tmds_clk_p,
            tmds_clock_n => O_tmds_clk_n,
            cx => cx,
            cy => cy,
            screen_start_x => open,
            screen_start_y => open,
            screen_width => open,
            screen_height => open
        );

    -- Output assignments
    O_tmds_data_p <= tmds_p_internal;
    O_tmds_data_n <= tmds_n_internal;

    -- LED status indicators (active low)
    O_led_n(0) <= not pll_locked;           -- PLL locked indicator
    O_led_n(1) <= not video_active;         -- Video active indicator
    O_led_n(2) <= not audio_enable;         -- Audio enabled indicator
    O_led_n(5 downto 3) <= not current_pattern;  -- Current pattern number

end rtl;