library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- HDMI_ENCODER: Top-level HDMI TMDS encoder and serializer for 24-bit RGB video
entity HDMI_ENCODER is
    port (
        -- Clock and reset
        clk_25mhz_pixel  : in  std_logic;  -- 25 MHz HDMI pixel clock
        clk_125mhz_tmds  : in  std_logic;  -- 125 MHz TMDS serialization clock
        reset            : in  std_logic;
        
        -- Video input
        rgb           : in  std_logic_vector(23 downto 0);  -- R(7:0), G(7:0), B(7:0)
        hsync         : in  std_logic;                      -- Horizontal sync
        vsync         : in  std_logic;                      -- Vertical sync
        de            : in  std_logic;                      -- Data enable (active video)
        
        -- HDMI output (differential pairs)
        hdmi_tx_clk_p : out std_logic;                      -- TMDS clock positive
        hdmi_tx_clk_n : out std_logic;                      -- TMDS clock negative
        hdmi_tx_p     : out std_logic_vector(2 downto 0);   -- TMDS data positive (RGB)
        hdmi_tx_n     : out std_logic_vector(2 downto 0)    -- TMDS data negative (RGB)
    );
end HDMI_ENCODER;

architecture RTL of HDMI_ENCODER is

    -- TMDS encoding components for each color channel
    component TMDS_ENCODER
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            data      : in  std_logic_vector(7 downto 0);   -- 8-bit color data
            c0        : in  std_logic;                      -- Control 0 (hsync for blue)
            c1        : in  std_logic;                      -- Control 1 (vsync for blue)
            de        : in  std_logic;                      -- Data enable
            encoded   : out std_logic_vector(9 downto 0)    -- 10-bit TMDS output
        );
    end component;
    
    -- OSER10: 10:1 serializer primitive for TMDS bitstream
    component OSER10
        generic (
            GSREN: STRING := "false";
            LSREN: STRING := "true"
        );
        port (
            Q: out std_logic;           -- Serialized output
            D0: in std_logic;           -- Bit 0
            D1: in std_logic;           -- Bit 1
            D2: in std_logic;           -- Bit 2
            D3: in std_logic;           -- Bit 3
            D4: in std_logic;           -- Bit 4
            D5: in std_logic;           -- Bit 5
            D6: in std_logic;           -- Bit 6
            D7: in std_logic;           -- Bit 7
            D8: in std_logic;           -- Bit 8
            D9: in std_logic;           -- Bit 9
            PCLK: in std_logic;         -- Pixel clock (25 MHz)
            FCLK: in std_logic;         -- Fast clock (125 MHz)
            RESET: in std_logic         -- Reset
        );
    end component;
    
    -- ELVDS_OBUF: Emulated LVDS Output Buffer for Tang Nano 9K
    component ELVDS_OBUF
        port (
            I  : in  std_logic;   -- Input signal
            O  : out std_logic;   -- Positive output
            OB : out std_logic    -- Negative output (automatically inverted)
        );
    end component;

    -- Internal signals for TMDS encoded data
    signal tmds_red     : std_logic_vector(9 downto 0);   -- TMDS encoded red
    signal tmds_green   : std_logic_vector(9 downto 0);   -- TMDS encoded green
    signal tmds_blue    : std_logic_vector(9 downto 0);   -- TMDS encoded blue

    -- Registered TMDS words (improves timing into serializers)
    signal tmds_red_r   : std_logic_vector(9 downto 0);
    signal tmds_green_r : std_logic_vector(9 downto 0);
    signal tmds_blue_r  : std_logic_vector(9 downto 0);

    -- Serialized bitstreams for each channel
    signal serial_red   : std_logic;                      -- Serialized red
    signal serial_green : std_logic;                      -- Serialized green
    signal serial_blue  : std_logic;                      -- Serialized blue
    signal serial_clk   : std_logic;                      -- Serialized TMDS clock

    -- Constant TMDS clock pattern: 5 low, then 5 high -> 25 MHz 50% duty
    constant CLK_TMDS_PATTERN : std_logic_vector(9 downto 0) := "0000011111";
    
    

begin

    -- Register TMDS words at pixel clock for better timing closure
    process(clk_25mhz_pixel)
    begin
        if rising_edge(clk_25mhz_pixel) then
            if reset = '1' then
                tmds_red_r   <= (others => '0');
                tmds_green_r <= (others => '0');
                tmds_blue_r  <= (others => '0');
            else
                tmds_red_r   <= tmds_red;
                tmds_green_r <= tmds_green;
                tmds_blue_r  <= tmds_blue;
            end if;
        end if;
    end process;

    -- TMDS encoders for each color channel
    encoder_red: TMDS_ENCODER
        port map (
            clk     => clk_25mhz_pixel,
            reset   => reset,
            data    => rgb(23 downto 16),  -- Red
            c0      => '0',                -- Not used for red
            c1      => '0',                -- Not used for red
            de      => de,
            encoded => tmds_red
        );
        
    encoder_green: TMDS_ENCODER
        port map (
            clk     => clk_25mhz_pixel,
            reset   => reset,
            data    => rgb(15 downto 8),   -- Green
            c0      => '0',                -- Not used for green
            c1      => '0',                -- Not used for green
            de      => de,
            encoded => tmds_green
        );
        
    encoder_blue: TMDS_ENCODER
        port map (
            clk     => clk_25mhz_pixel,
            reset   => reset,
            data    => rgb(7 downto 0),    -- Blue
            c0      => hsync,              -- hsync for blue channel
            c1      => vsync,              -- vsync for blue channel
            de      => de,
            encoded => tmds_blue
        );

    -- OSER10 per channel (10:1 at 5x with DDR)
    -- Serializes 10-bit TMDS data to 1-bit stream for each channel
    serializer_red: OSER10
        generic map (
            GSREN => "false",
            LSREN => "true"
        )
        port map (
            Q       => serial_red,
            D0      => tmds_red_r(0),
            D1      => tmds_red_r(1),
            D2      => tmds_red_r(2),
            D3      => tmds_red_r(3),
            D4      => tmds_red_r(4),
            D5      => tmds_red_r(5),
            D6      => tmds_red_r(6),
            D7      => tmds_red_r(7),
            D8      => tmds_red_r(8),
            D9      => tmds_red_r(9),
            PCLK    => clk_25mhz_pixel,
            FCLK    => clk_125mhz_tmds,
            RESET   => reset
        );

    serializer_green: OSER10
        generic map (
            GSREN => "false",
            LSREN => "true"
        )
        port map (
            Q       => serial_green,
            D0      => tmds_green_r(0),
            D1      => tmds_green_r(1),
            D2      => tmds_green_r(2),
            D3      => tmds_green_r(3),
            D4      => tmds_green_r(4),
            D5      => tmds_green_r(5),
            D6      => tmds_green_r(6),
            D7      => tmds_green_r(7),
            D8      => tmds_green_r(8),
            D9      => tmds_green_r(9),
            PCLK    => clk_25mhz_pixel,
            FCLK    => clk_125mhz_tmds,
            RESET   => reset
        );

    serializer_blue: OSER10
        generic map (
            GSREN => "false",
            LSREN => "true"
        )
        port map (
            Q       => serial_blue,
            D0      => tmds_blue_r(0),
            D1      => tmds_blue_r(1),
            D2      => tmds_blue_r(2),
            D3      => tmds_blue_r(3),
            D4      => tmds_blue_r(4),
            D5      => tmds_blue_r(5),
            D6      => tmds_blue_r(6),
            D7      => tmds_blue_r(7),
            D8      => tmds_blue_r(8),
            D9      => tmds_blue_r(9),
            PCLK    => clk_25mhz_pixel,
            FCLK    => clk_125mhz_tmds,
            RESET   => reset
        );

    -- TMDS clock pattern: 5 low bits, then 5 high bits (for 25 MHz clock)
    serializer_clk: OSER10
        generic map (
            GSREN => "false",
            LSREN => "true"
        )
        port map (
            Q       => serial_clk,
            D0      => CLK_TMDS_PATTERN(0),
            D1      => CLK_TMDS_PATTERN(1),
            D2      => CLK_TMDS_PATTERN(2),
            D3      => CLK_TMDS_PATTERN(3),
            D4      => CLK_TMDS_PATTERN(4),
            D5      => CLK_TMDS_PATTERN(5),
            D6      => CLK_TMDS_PATTERN(6),
            D7      => CLK_TMDS_PATTERN(7),
            D8      => CLK_TMDS_PATTERN(8),
            D9      => CLK_TMDS_PATTERN(9),
            PCLK    => clk_25mhz_pixel,
            FCLK    => clk_125mhz_tmds,
            RESET   => reset
        );

    -- ELVDS_OBUF instantiations for Tang Nano 9K emulated LVDS output
    -- Each differential pair needs its own ELVDS_OBUF component
    
    -- Red channel differential output
    elvds_red: ELVDS_OBUF
        port map (
            I  => serial_red,
            O  => hdmi_tx_p(2),  -- Red positive
            OB => hdmi_tx_n(2)   -- Red negative (auto-inverted)
        );
    
    -- Green channel differential output    
    elvds_green: ELVDS_OBUF
        port map (
            I  => serial_green,
            O  => hdmi_tx_p(1),  -- Green positive
            OB => hdmi_tx_n(1)   -- Green negative (auto-inverted)
        );
    
    -- Blue channel differential output
    elvds_blue: ELVDS_OBUF
        port map (
            I  => serial_blue,
            O  => hdmi_tx_p(0),  -- Blue positive
            OB => hdmi_tx_n(0)   -- Blue negative (auto-inverted)
        );
    
    -- Clock differential output
    elvds_clk: ELVDS_OBUF
        port map (
            I  => serial_clk,
            O  => hdmi_tx_clk_p, -- Clock positive
            OB => hdmi_tx_clk_n  -- Clock negative (auto-inverted)
        );

end RTL;