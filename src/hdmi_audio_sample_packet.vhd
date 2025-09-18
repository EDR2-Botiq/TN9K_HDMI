-------------------------------------------------------------------------------
-- hdmi_audio_sample_packet.vhd
-- HDMI audio sample packet implementation (based on VIC20Nano)
-- Implements proper IEC 60958 frames with consumer grade format
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_audio_sample_packet is
    generic (
        -- IEC 60958-3 parameters
        GRADE                       : std_logic := '0';     -- 0 = Consumer, 1 = Professional
        SAMPLE_WORD_TYPE           : std_logic := '0';     -- 0 = LPCM, 1 = IEC 61937 compressed
        COPYRIGHT_NOT_ASSERTED     : std_logic := '1';     -- 0 = asserted, 1 = not asserted
        PRE_EMPHASIS              : std_logic_vector(2 downto 0) := "000"; -- 000 = no pre-emphasis
        MODE                       : std_logic_vector(1 downto 0) := "00";  -- Only valid value
        CATEGORY_CODE              : std_logic_vector(7 downto 0) := x"00"; -- General device
        SOURCE_NUMBER              : std_logic_vector(3 downto 0) := x"0";  -- Do not take into account
        SAMPLING_FREQUENCY         : std_logic_vector(3 downto 0) := "0010"; -- 48 kHz (0010)
        CLOCK_ACCURACY             : std_logic_vector(1 downto 0) := "00";   -- Normal accuracy
        WORD_LENGTH                : std_logic_vector(3 downto 0) := "0000"; -- 16-bit
        ORIGINAL_SAMPLING_FREQUENCY: std_logic_vector(3 downto 0) := "0000"; -- Not indicated
        LAYOUT                     : std_logic := '0'       -- 0 = 2-channel, 1 = >= 3-channel
    );
    port (
        -- Frame counter for channel status
        frame_counter           : in  std_logic_vector(7 downto 0);

        -- IEC 60958 data
        valid_bit_left          : in  std_logic_vector(1 downto 0);  -- 0 = suitable for analog decode
        valid_bit_right         : in  std_logic_vector(1 downto 0);
        user_data_bit_left      : in  std_logic_vector(1 downto 0);  -- 0 = no user data
        user_data_bit_right     : in  std_logic_vector(1 downto 0);

        -- Audio sample words (4 subframes, 2 channels each)
        audio_sample_word_left  : in  std_logic_vector(23 downto 0);
        audio_sample_word_right : in  std_logic_vector(23 downto 0);
        audio_sample_word_present : in std_logic_vector(3 downto 0);

        -- HDMI packet outputs
        header                  : out std_logic_vector(23 downto 0);
        sub0                    : out std_logic_vector(55 downto 0);
        sub1                    : out std_logic_vector(55 downto 0);
        sub2                    : out std_logic_vector(55 downto 0);
        sub3                    : out std_logic_vector(55 downto 0)
    );
end entity;

architecture rtl of hdmi_audio_sample_packet is

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

    -- Channel identifiers for stereo audio
    constant CHANNEL_LEFT  : std_logic_vector(3 downto 0) := x"1";
    constant CHANNEL_RIGHT : std_logic_vector(3 downto 0) := x"2";

    -- Channel status length
    constant CHANNEL_STATUS_LENGTH : integer := 192;

    -- Channel status vectors (see IEC 60958-1 5.1, Table 2)
    signal channel_status_left  : std_logic_vector(191 downto 0);
    signal channel_status_right : std_logic_vector(191 downto 0);

    -- Frame counter alignment for channel status
    type aligned_frame_array_t is array (0 to 3) of std_logic_vector(7 downto 0);
    signal aligned_frame_counter : aligned_frame_array_t;

    -- Parity bits for each subframe
    type parity_array_t is array (0 to 3) of std_logic_vector(1 downto 0);
    signal parity_bit : parity_array_t;

    -- Parity calculation function
    function calc_parity(
        channel_status_bit : std_logic;
        user_data_bit     : std_logic;
        valid_bit         : std_logic;
        audio_sample_word : std_logic_vector(23 downto 0)
    ) return std_logic is
        variable parity : std_logic;
    begin
        parity := channel_status_bit xor user_data_bit xor valid_bit;
        for i in 0 to 23 loop
            parity := parity xor audio_sample_word(i);
        end loop;
        return parity;
    end function;

begin

    -- Build channel status vectors
    channel_status_left <= (191 downto 40 => '0') &
                          ORIGINAL_SAMPLING_FREQUENCY &
                          WORD_LENGTH &
                          "00" &  -- Reserved
                          CLOCK_ACCURACY &
                          SAMPLING_FREQUENCY &
                          CHANNEL_LEFT &
                          SOURCE_NUMBER &
                          CATEGORY_CODE &
                          MODE &
                          PRE_EMPHASIS &
                          COPYRIGHT_NOT_ASSERTED &
                          SAMPLE_WORD_TYPE &
                          GRADE;

    channel_status_right <= (191 downto 40 => '0') &
                           ORIGINAL_SAMPLING_FREQUENCY &
                           WORD_LENGTH &
                           "00" &  -- Reserved
                           CLOCK_ACCURACY &
                           SAMPLING_FREQUENCY &
                           CHANNEL_RIGHT &
                           SOURCE_NUMBER &
                           CATEGORY_CODE &
                           MODE &
                           PRE_EMPHASIS &
                           COPYRIGHT_NOT_ASSERTED &
                           SAMPLE_WORD_TYPE &
                           GRADE;

    -- Frame counter alignment (handle wrap-around at 192)
    gen_frame_alignment: for i in 0 to 3 generate
        process(frame_counter)
            variable temp_counter : integer;
        begin
            temp_counter := to_integer(unsigned(frame_counter)) + i;
            if temp_counter >= CHANNEL_STATUS_LENGTH then
                aligned_frame_counter(i) <= std_logic_vector(to_unsigned(temp_counter - CHANNEL_STATUS_LENGTH, 8));
            else
                aligned_frame_counter(i) <= std_logic_vector(to_unsigned(temp_counter, 8));
            end if;
        end process;
    end generate;

    -- Parity calculation for each subframe
    gen_parity: for i in 0 to 3 generate
        parity_bit(i)(0) <= calc_parity(
            channel_status_left(to_integer(unsigned(aligned_frame_counter(i)))),
            user_data_bit_left(0),
            valid_bit_left(0),
            audio_sample_word_left
        );

        parity_bit(i)(1) <= calc_parity(
            channel_status_right(to_integer(unsigned(aligned_frame_counter(i)))),
            user_data_bit_right(0),
            valid_bit_right(0),
            audio_sample_word_right
        );
    end generate;

    -- HDMI Audio Sample Packet Header (see Table 5-12)
    header(23) <= '1' when (unsigned(aligned_frame_counter(0)) = 0 and audio_sample_word_present(0) = '1') else '0';
    header(22) <= '1' when (unsigned(aligned_frame_counter(1)) = 0 and audio_sample_word_present(1) = '1') else '0';
    header(21) <= '1' when (unsigned(aligned_frame_counter(2)) = 0 and audio_sample_word_present(2) = '1') else '0';
    header(20) <= '1' when (unsigned(aligned_frame_counter(3)) = 0 and audio_sample_word_present(3) = '1') else '0';
    header(19 downto 12) <= "0000" & "000" & LAYOUT;
    header(11) <= audio_sample_word_present(0);
    header(10) <= audio_sample_word_present(1);
    header(9)  <= audio_sample_word_present(2);
    header(8)  <= audio_sample_word_present(3);
    header(7 downto 0) <= x"02";  -- Audio Sample Packet type

    -- Audio Sample Subpackets (see Table 5-13)
    gen_subpackets: for i in 0 to 3 generate
        process(audio_sample_word_present, parity_bit, channel_status_left, channel_status_right,
                user_data_bit_left, user_data_bit_right, valid_bit_left, valid_bit_right,
                audio_sample_word_left, audio_sample_word_right, aligned_frame_counter)
        begin
            if audio_sample_word_present(i) = '1' then
                case i is
                    when 0 =>
                        sub0 <= parity_bit(0)(1) &
                               channel_status_right(to_integer(unsigned(aligned_frame_counter(0)))) &
                               user_data_bit_right(0) &
                               valid_bit_right(0) &
                               parity_bit(0)(0) &
                               channel_status_left(to_integer(unsigned(aligned_frame_counter(0)))) &
                               user_data_bit_left(0) &
                               valid_bit_left(0) &
                               audio_sample_word_right &
                               audio_sample_word_left;
                    when 1 =>
                        sub1 <= parity_bit(1)(1) &
                               channel_status_right(to_integer(unsigned(aligned_frame_counter(1)))) &
                               user_data_bit_right(0) &
                               valid_bit_right(0) &
                               parity_bit(1)(0) &
                               channel_status_left(to_integer(unsigned(aligned_frame_counter(1)))) &
                               user_data_bit_left(0) &
                               valid_bit_left(0) &
                               audio_sample_word_right &
                               audio_sample_word_left;
                    when 2 =>
                        sub2 <= parity_bit(2)(1) &
                               channel_status_right(to_integer(unsigned(aligned_frame_counter(2)))) &
                               user_data_bit_right(0) &
                               valid_bit_right(0) &
                               parity_bit(2)(0) &
                               channel_status_left(to_integer(unsigned(aligned_frame_counter(2)))) &
                               user_data_bit_left(0) &
                               valid_bit_left(0) &
                               audio_sample_word_right &
                               audio_sample_word_left;
                    when 3 =>
                        sub3 <= parity_bit(3)(1) &
                               channel_status_right(to_integer(unsigned(aligned_frame_counter(3)))) &
                               user_data_bit_right(0) &
                               valid_bit_right(0) &
                               parity_bit(3)(0) &
                               channel_status_left(to_integer(unsigned(aligned_frame_counter(3)))) &
                               user_data_bit_left(0) &
                               valid_bit_left(0) &
                               audio_sample_word_right &
                               audio_sample_word_left;
                    when others =>
                        null;
                end case;
            else
                case i is
                    when 0 => sub0 <= (others => '0');
                    when 1 => sub1 <= (others => '0');
                    when 2 => sub2 <= (others => '0');
                    when 3 => sub3 <= (others => '0');
                    when others => null;
                end case;
            end if;
        end process;
    end generate;

end rtl;