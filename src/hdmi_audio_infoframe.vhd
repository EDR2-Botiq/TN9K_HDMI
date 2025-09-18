-------------------------------------------------------------------------------
-- hdmi_audio_infoframe.vhd
-- Audio InfoFrame packet generator for HDMI audio metadata
-- Generates IEC 60958-3 compliant Audio InfoFrame packets per HDMI spec
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_audio_infoframe is
    port (
        clk_pixel           : in  std_logic;
        reset               : in  std_logic;

        -- InfoFrame configuration (static for basic stereo)
        channel_count       : in  std_logic_vector(2 downto 0) := "001";  -- 2 channels (stereo)
        sample_frequency    : in  std_logic_vector(2 downto 0) := "010";  -- 48 kHz
        sample_size         : in  std_logic_vector(1 downto 0) := "01";   -- 16-bit

        -- HDMI packet outputs
        header              : out std_logic_vector(23 downto 0);
        sub0                : out std_logic_vector(55 downto 0);
        sub1                : out std_logic_vector(55 downto 0);
        sub2                : out std_logic_vector(55 downto 0);
        sub3                : out std_logic_vector(55 downto 0)
    );
end entity;

architecture rtl of hdmi_audio_infoframe is

    -- Audio InfoFrame Type and Version (per HDMI 1.4 spec)
    constant INFOFRAME_TYPE    : std_logic_vector(7 downto 0) := x"84";  -- Audio InfoFrame
    constant INFOFRAME_VERSION : std_logic_vector(7 downto 0) := x"01";  -- Version 1
    constant INFOFRAME_LENGTH  : std_logic_vector(7 downto 0) := x"0A";  -- 10 bytes

    -- Audio InfoFrame payload bytes
    signal payload_byte1 : std_logic_vector(7 downto 0);  -- Channel count & coding type
    signal payload_byte2 : std_logic_vector(7 downto 0);  -- Sample freq & size
    signal payload_byte3 : std_logic_vector(7 downto 0);  -- Reserved
    signal payload_byte4 : std_logic_vector(7 downto 0);  -- Channel allocation
    signal payload_byte5 : std_logic_vector(7 downto 0);  -- Reserved/downmix

    -- Checksum calculation
    signal checksum_temp : unsigned(8 downto 0);
    signal checksum      : std_logic_vector(7 downto 0);

    -- Synthesis attributes to prevent optimization
    attribute keep : string;
    attribute syn_keep : string;
    attribute keep of header : signal is "true";
    attribute keep of sub0 : signal is "true";
    attribute keep of sub1 : signal is "true";
    attribute keep of sub2 : signal is "true";
    attribute keep of sub3 : signal is "true";
    attribute syn_keep of header : signal is "true";
    attribute syn_keep of sub0 : signal is "true";
    attribute syn_keep of sub1 : signal is "true";
    attribute syn_keep of sub2 : signal is "true";
    attribute syn_keep of sub3 : signal is "true";

begin

    -- Build Audio InfoFrame payload
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            payload_byte1 <= (others => '0');
            payload_byte2 <= (others => '0');
            payload_byte3 <= (others => '0');
            payload_byte4 <= (others => '0');
            payload_byte5 <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Byte 1: Channel Count (bits 2:0) and Coding Type (bits 6:4)
            -- CT=0 (refer to stream header), CC=channel_count-1
            payload_byte1 <= "0" & "000" & "0" & std_logic_vector(unsigned(channel_count) - 1);

            -- Byte 2: Sample Frequency (bits 4:2) and Sample Size (bits 1:0)
            -- SF=sample_frequency, SS=sample_size
            payload_byte2 <= "0" & sample_frequency & "00" & sample_size;

            -- Byte 3: Reserved (all zeros)
            payload_byte3 <= x"00";

            -- Byte 4: Channel Allocation (0 for stereo L/R)
            payload_byte4 <= x"00";

            -- Byte 5: Downmix inhibit and reserved bits
            payload_byte5 <= x"00";
        end if;
    end process;

    -- Calculate checksum (two's complement)
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            checksum_temp <= (others => '0');
            checksum <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Sum all header and payload bytes
            checksum_temp <= ('0' & unsigned(INFOFRAME_TYPE)) +
                            ('0' & unsigned(INFOFRAME_VERSION)) +
                            ('0' & unsigned(INFOFRAME_LENGTH)) +
                            ('0' & unsigned(payload_byte1)) +
                            ('0' & unsigned(payload_byte2)) +
                            ('0' & unsigned(payload_byte3)) +
                            ('0' & unsigned(payload_byte4)) +
                            ('0' & unsigned(payload_byte5));

            -- Two's complement for checksum
            checksum <= std_logic_vector(256 - unsigned(checksum_temp(7 downto 0)));
        end if;
    end process;

    -- Assemble HDMI packet structure
    -- Header: [HB2, HB1, HB0] = [Length, Version, Type]
    header <= INFOFRAME_LENGTH & INFOFRAME_VERSION & INFOFRAME_TYPE;

    -- Sub-packet 0: [PB6, PB5, PB4, PB3, PB2, PB1, PB0] = [0, Byte5, Byte4, Byte3, Byte2, Byte1, Checksum]
    sub0 <= x"00" & payload_byte5 & payload_byte4 & payload_byte3 & payload_byte2 & payload_byte1 & checksum;

    -- Sub-packets 1-3: All zeros (Audio InfoFrame payload is only 10 bytes)
    sub1 <= (others => '0');
    sub2 <= (others => '0');
    sub3 <= (others => '0');

end architecture;