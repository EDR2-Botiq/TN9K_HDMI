library ieee;
use ieee.std_logic_1164.all;

package hdmi_package is
    -- HDMI Core Component Declaration
    component hdmi
        generic (
            VIDEO_ID_CODE : integer := 200;  -- Custom code for 800x480
            IT_CONTENT : std_logic := '1';
            BIT_WIDTH : integer := 11;
            BIT_HEIGHT : integer := 10;
            DVI_OUTPUT : std_logic := '0';
            VIDEO_REFRESH_RATE : real := 60.0;
            AUDIO_RATE : integer := 48000;
            AUDIO_BIT_WIDTH : integer := 16;
            VENDOR_NAME : std_logic_vector(63 downto 0) := x"54616E674E616E6F";  -- "TangNano"
            PRODUCT_DESCRIPTION : std_logic_vector(127 downto 0) := x"465047412D44656D6F20202020202000";  -- "FPGA-Demo    \0"
            SOURCE_DEVICE_INFORMATION : std_logic_vector(7 downto 0) := x"00";
            START_X : integer := 0;
            START_Y : integer := 0
        );
        port (
            clk_pixel_x5 : in std_logic;
            clk_pixel : in std_logic;
            clk_audio : in std_logic;
            reset : in std_logic;
            rgb : in std_logic_vector(23 downto 0);
            audio_sample_word_0 : in std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);  -- Left channel
            audio_sample_word_1 : in std_logic_vector(AUDIO_BIT_WIDTH-1 downto 0);  -- Right channel
            tmds : out std_logic_vector(2 downto 0);
            tmds_clock : out std_logic;
            cx : out std_logic_vector(10 downto 0);
            cy : out std_logic_vector(9 downto 0);
            frame_width : out std_logic_vector(10 downto 0);
            frame_height : out std_logic_vector(9 downto 0);
            screen_width : out std_logic_vector(10 downto 0);
            screen_height : out std_logic_vector(9 downto 0)
        );
    end component;
end package hdmi_package;