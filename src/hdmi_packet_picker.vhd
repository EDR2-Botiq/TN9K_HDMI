-------------------------------------------------------------------------------
-- hdmi_packet_picker.vhd - VIC20Nano-Inspired HDMI Packet Scheduler
-- Advanced packet selection logic based on VIC20Nano's proven architecture
--
-- VIC20NANO PACKET ARCHITECTURE OVERVIEW:
-- =======================================
-- The VIC20Nano project established the gold standard for HDMI audio packet
-- scheduling in retro FPGA implementations. This module implements their
-- proven techniques for reliable audio transport over HDMI data islands.
--
-- KEY VIC20NANO DESIGN PRINCIPLES:
-- - Case-statement packet selection (not sparse memory arrays)
-- - Efficient bandwidth utilization with minimal resource overhead
-- - Robust timing management for real-time audio streaming
-- - Synthesis-friendly architecture that prevents optimization issues
--
-- PACKET TYPES MANAGED:
-- - Audio Clock Regeneration (ACR): Synchronizes audio sample rate with pixel clock
-- - Audio Sample Packets (ASP): IEC 60958 formatted PCM audio data
-- - InfoFrames: Display metadata (disabled by default for stability)
--
-- BANDWIDTH EFFICIENCY:
-- Following VIC20Nano's approach, this scheduler maximizes useful audio data
-- transport while maintaining HDMI compliance and video sync integrity.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_constants.all;

entity hdmi_packet_picker is
    generic (
        -- VIC20NANO AUDIO CONFIGURATION:
        AUDIO_RATE        : integer := AUDIO_SAMPLE_FREQ;  -- 48 kHz standard rate

        -- VIC20NANO PACKET ENABLE STRATEGY:
        -- Runtime controls allow dynamic packet management vs compile-time optimization
        ENABLE_ACR        : boolean := true;   -- Audio Clock Regeneration (essential)
        ENABLE_ASP        : boolean := true;   -- Audio Sample Packets (core audio data)
        ENABLE_INFOFRAME  : boolean := true;   -- InfoFrames (audio metadata)

        -- VIC20NANO BANDWIDTH OPTIMIZATION:
        -- Single subframe mode reduces bandwidth requirements while maintaining quality
        ASP_SINGLE_SUBFRAME: boolean := true   -- Use only first subframe for efficiency
    );
    port (
        clk_pixel           : in  std_logic;
        clk_audio           : in  std_logic;
        reset               : in  std_logic;

        -- Timing signals
        video_field_end     : in  std_logic;
        packet_enable       : in  std_logic;
        packet_pixel_counter: in  std_logic_vector(4 downto 0);

        -- Audio inputs
        audio_sample_word_left  : in  std_logic_vector(23 downto 0);
        audio_sample_word_right : in  std_logic_vector(23 downto 0);
        clk_audio_counter_wrap  : in  std_logic;
    -- ACR values from hdmi_audio_acr (ensures module isn't optimized away)
    acr_n               : in  std_logic_vector(19 downto 0);
    acr_cts             : in  std_logic_vector(19 downto 0);

        -- Packet outputs
        header              : out std_logic_vector(23 downto 0);
        sub0                : out std_logic_vector(55 downto 0);
        sub1                : out std_logic_vector(55 downto 0);
        sub2                : out std_logic_vector(55 downto 0);
        sub3                : out std_logic_vector(55 downto 0)
    );
end entity;

architecture rtl of hdmi_packet_picker is

    -- Packet type selection
    signal packet_type : std_logic_vector(7 downto 0) := (others => '0');

    -- Audio sample buffer management
    -- Simplified single-sample buffers (remove unused array elements to avoid latch inference)
    signal audio_sample_word_buffer_left  : std_logic_vector(23 downto 0) := (others => '0');
    signal audio_sample_word_buffer_right : std_logic_vector(23 downto 0) := (others => '0');
    signal audio_sample_word_present_packet : std_logic_vector(3 downto 0);

    -- Sample buffer control
    signal sample_buffer_current    : std_logic := '0';
    signal sample_buffer_used       : std_logic := '0';
    signal sample_buffer_ready      : std_logic := '0';
    signal samples_remaining        : unsigned(1 downto 0) := (others => '0');

    -- Audio sample transfer from clk_audio domain
    signal audio_sample_word_transfer_left  : std_logic_vector(23 downto 0);
    signal audio_sample_word_transfer_right : std_logic_vector(23 downto 0);
    signal audio_sample_word_transfer_control : std_logic := '0';

    -- Clock domain crossing synchronizer
    signal audio_sample_word_transfer_control_sync : std_logic_vector(1 downto 0) := "00";

    -- Frame tracking
    signal audio_info_frame_sent    : std_logic := '0';
    signal last_clk_audio_counter_wrap : std_logic := '0';

    -- Frame counter for channel status
    signal frame_counter : unsigned(7 downto 0) := (others => '0');

    -- Packet generators
    component hdmi_audio_sample_packet is
        generic (
            SAMPLING_FREQUENCY : std_logic_vector(3 downto 0) := "0010"  -- 48 kHz
        );
        port (
            frame_counter           : in  std_logic_vector(7 downto 0);
            valid_bit_left          : in  std_logic_vector(1 downto 0);
            valid_bit_right         : in  std_logic_vector(1 downto 0);
            user_data_bit_left      : in  std_logic_vector(1 downto 0);
            user_data_bit_right     : in  std_logic_vector(1 downto 0);
            audio_sample_word_left  : in  std_logic_vector(23 downto 0);
            audio_sample_word_right : in  std_logic_vector(23 downto 0);
            audio_sample_word_present : in std_logic_vector(3 downto 0);
            header                  : out std_logic_vector(23 downto 0);
            sub0                    : out std_logic_vector(55 downto 0);
            sub1                    : out std_logic_vector(55 downto 0);
            sub2                    : out std_logic_vector(55 downto 0);
            sub3                    : out std_logic_vector(55 downto 0)
        );
    end component;

    -- Audio InfoFrame component
    component hdmi_audio_infoframe is
        port (
            clk_pixel           : in  std_logic;
            reset               : in  std_logic;
            channel_count       : in  std_logic_vector(2 downto 0);
            sample_frequency    : in  std_logic_vector(2 downto 0);
            sample_size         : in  std_logic_vector(1 downto 0);
            header              : out std_logic_vector(23 downto 0);
            sub0                : out std_logic_vector(55 downto 0);
            sub1                : out std_logic_vector(55 downto 0);
            sub2                : out std_logic_vector(55 downto 0);
            sub3                : out std_logic_vector(55 downto 0)
        );
    end component;

    -- ACR values now supplied by top-level (dynamic / prevents sweep)

    -- Audio Sample Packet outputs
    signal asp_header : std_logic_vector(23 downto 0);
    signal asp_sub0   : std_logic_vector(55 downto 0);
    signal asp_sub1   : std_logic_vector(55 downto 0);
    signal asp_sub2   : std_logic_vector(55 downto 0);
    signal asp_sub3   : std_logic_vector(55 downto 0);

    -- Audio InfoFrame Packet outputs
    signal aif_header : std_logic_vector(23 downto 0);
    signal aif_sub0   : std_logic_vector(55 downto 0);
    signal aif_sub1   : std_logic_vector(55 downto 0);
    signal aif_sub2   : std_logic_vector(55 downto 0);
    signal aif_sub3   : std_logic_vector(55 downto 0);

    -- Keep ASP outputs to prevent entire generator being swept during early bring-up
    attribute keep : string;
    attribute keep of asp_header : signal is "true";
    attribute keep of asp_sub0   : signal is "true";
    attribute keep of asp_sub1   : signal is "true";
    attribute keep of asp_sub2   : signal is "true";
    attribute keep of asp_sub3   : signal is "true";
    attribute keep of aif_header : signal is "true";
    attribute keep of aif_sub0   : signal is "true";
    attribute keep of aif_sub1   : signal is "true";
    attribute keep of aif_sub2   : signal is "true";
    attribute keep of aif_sub3   : signal is "true";

    -- Internal control derived from generics
    signal allow_acr       : boolean;
    signal allow_asp       : boolean;
    signal allow_infoframe : boolean;

begin

    -- Map generics to internal signals (could add runtime gating later)
    allow_acr       <= ENABLE_ACR;
    allow_asp       <= ENABLE_ASP;
    allow_infoframe <= ENABLE_INFOFRAME;

    -- Audio sample transfer from clk_audio domain
    process(clk_audio, reset)
    begin
        if reset = '1' then
            audio_sample_word_transfer_left <= (others => '0');
            audio_sample_word_transfer_right <= (others => '0');
            audio_sample_word_transfer_control <= '0';
        elsif rising_edge(clk_audio) then
            audio_sample_word_transfer_left <= audio_sample_word_left;
            audio_sample_word_transfer_right <= audio_sample_word_right;
            audio_sample_word_transfer_control <= not audio_sample_word_transfer_control;
        end if;
    end process;

    -- Clock domain crossing synchronizer
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            audio_sample_word_transfer_control_sync <= "00";
        elsif rising_edge(clk_pixel) then
            audio_sample_word_transfer_control_sync <=
                audio_sample_word_transfer_control & audio_sample_word_transfer_control_sync(1);
        end if;
    end process;

    -- Sample buffer management
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            sample_buffer_used <= '0';
            sample_buffer_ready <= '0';
            frame_counter <= (others => '0');
            audio_info_frame_sent <= '0';
            last_clk_audio_counter_wrap <= '0';
            packet_type <= (others => '0');
            audio_sample_word_buffer_left <= (others => '0');
            audio_sample_word_buffer_right <= (others => '0');
            audio_sample_word_present_packet <= (others => '0');
        elsif rising_edge(clk_pixel) then

            if sample_buffer_used = '1' then
                sample_buffer_used <= '0';
                sample_buffer_ready <= '0';  -- Clear ready flag when buffer is consumed
            end if;

            -- Handle new audio samples
            if audio_sample_word_transfer_control_sync(0) /= audio_sample_word_transfer_control_sync(1) then
                audio_sample_word_buffer_left <= audio_sample_word_transfer_left;
                audio_sample_word_buffer_right <= audio_sample_word_transfer_right;
                sample_buffer_ready <= '1';
                frame_counter <= frame_counter + 1;
            end if;

            -- Reset frame flags at end of video field
            if reset = '1' or video_field_end = '1' then
                audio_info_frame_sent <= '0';
                packet_type <= (others => '0');
            elsif packet_enable = '1' then
                -- Priority: ACR > ASP > InfoFrame > NULL
                if allow_acr and (last_clk_audio_counter_wrap /= clk_audio_counter_wrap) then
                    packet_type <= x"01";  -- ACR
                    last_clk_audio_counter_wrap <= clk_audio_counter_wrap;
                elsif allow_asp and sample_buffer_ready = '1' then
                    packet_type <= x"02";  -- Audio Sample
                    if ASP_SINGLE_SUBFRAME then
                        audio_sample_word_present_packet <= "0001";  -- one subframe
                    else
                        audio_sample_word_present_packet <= "1111";  -- all (future expansion)
                    end if;
                    sample_buffer_used <= '1';
                elsif allow_infoframe and (audio_info_frame_sent = '0') then
                    packet_type <= x"84";  -- Audio Info Frame
                    audio_info_frame_sent <= '1';
                else
                    packet_type <= x"00";  -- NULL
                end if;
            end if;
        end if;
    end process;

    -- Audio Sample Packet generator
    audio_sample_packet_inst: hdmi_audio_sample_packet
        generic map (
            SAMPLING_FREQUENCY => SAMPLING_FREQ_CODE  -- 48 kHz
        )
        port map (
            frame_counter => std_logic_vector(frame_counter),
            valid_bit_left => "00",
            valid_bit_right => "00",
            user_data_bit_left => "00",
            user_data_bit_right => "00",
            audio_sample_word_left => audio_sample_word_buffer_left,
            audio_sample_word_right => audio_sample_word_buffer_right,
            audio_sample_word_present => audio_sample_word_present_packet,
            header => asp_header,
            sub0 => asp_sub0,
            sub1 => asp_sub1,
            sub2 => asp_sub2,
            sub3 => asp_sub3
        );

    -- VIC20NANO PACKET MULTIPLEXING STRATEGY:
    -- ========================================
    -- This case-statement approach is a key VIC20Nano innovation that replaces
    -- large memory arrays with efficient combinatorial logic. Benefits:
    -- 1. Minimal resource usage (no BRAM/LUT memory)
    -- 2. Fast synthesis and timing closure
    -- 3. Synthesis-friendly structure prevents optimization issues
    -- 4. Easy to understand and maintain
    process(packet_type, asp_header, asp_sub0, asp_sub1, asp_sub2, asp_sub3, aif_header, aif_sub0, aif_sub1, aif_sub2, aif_sub3, acr_n, acr_cts)
    begin
        case packet_type is
            when x"00" =>  -- NULL PACKET (HDMI idle state)
                -- Used during unused data island periods
                header <= (others => '0');
                sub0 <= (others => '0');
                sub1 <= (others => '0');
                sub2 <= (others => '0');
                sub3 <= (others => '0');

            when x"01" =>  -- AUDIO CLOCK REGENERATION (ACR) PACKET
                -- VIC20Nano essential: Synchronizes audio sample rate to pixel clock
                -- Format: Header(24) + N(20) + CTS(20) parameters
                header <= x"010000";  -- ACR packet type, no HB1/HB2
                sub0 <= (39 downto 0 => '0') & acr_cts(7 downto 0) & acr_n(7 downto 0);
                sub1 <= (39 downto 0 => '0') & acr_cts(15 downto 8) & acr_n(15 downto 8);
                sub2 <= (51 downto 0 => '0') & acr_cts(19 downto 16);  -- CTS upper bits
                sub3 <= (51 downto 0 => '0') & acr_n(19 downto 16);    -- N upper bits

            when x"02" =>  -- AUDIO SAMPLE PACKET (ASP) - CORE AUDIO DATA
                -- VIC20Nano primary audio transport: IEC 60958 formatted PCM samples
                -- Generated by hdmi_audio_sample_packet with proper channel formatting
                header <= asp_header;  -- Includes sample present flags and metadata
                sub0 <= asp_sub0;      -- Audio subframe 0 (left channel primary)
                sub1 <= asp_sub1;      -- Audio subframe 1 (right channel primary)
                sub2 <= asp_sub2;      -- Audio subframe 2 (left channel secondary)
                sub3 <= asp_sub3;      -- Audio subframe 3 (right channel secondary)

            when x"84" =>  -- AUDIO INFO FRAME (Proper metadata)
                -- VIC20Nano compatible: Full HDMI-compliant Audio InfoFrame
                header <= aif_header;  -- Proper InfoFrame header with checksum
                sub0 <= aif_sub0;      -- Audio parameters (channels, sample rate, etc.)
                sub1 <= aif_sub1;      -- Extended audio metadata (usually zeros)
                sub2 <= aif_sub2;      -- Speaker allocation (stereo = zeros)
                sub3 <= aif_sub3;      -- Additional metadata (usually zeros)

            when others =>  -- Default to NULL packet
                header <= (others => '0');
                sub0 <= (others => '0');
                sub1 <= (others => '0');
                sub2 <= (others => '0');
                sub3 <= (others => '0');
        end case;
    end process;

    -- Audio InfoFrame generator (provides proper HDMI audio metadata)
    audio_infoframe_inst : hdmi_audio_infoframe
        port map (
            clk_pixel        => clk_pixel,
            reset            => reset,
            channel_count    => "001",    -- 2 channels (stereo)
            sample_frequency => "010",    -- 48 kHz
            sample_size      => "01",     -- 16-bit
            header           => aif_header,
            sub0             => aif_sub0,
            sub1             => aif_sub1,
            sub2             => aif_sub2,
            sub3             => aif_sub3
        );

end rtl;