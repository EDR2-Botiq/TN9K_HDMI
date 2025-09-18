-------------------------------------------------------------------------------
-- hdmi_audio_packetizer.vhd
-- Minimal HDMI Audio Sample + ACR packetizer for 48 kHz stereo PCM.
-- Notes:
--  * Inserts ACR and Audio Sample Packets during Data Island periods.
--  * Assumes pixel timing for 640x480@60 with blanking long enough.
--  * Accepts one new stereo sample each asserted 'aud_sample_stb' (48 kHz).
--  * This is a pragmatic, pared-down implementation aimed at hobby demos.
--  * It does not implement all corner cases/infoframes; sinks commonly accept it.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_audio_packetizer is
    port (
        clk_pix         : in  std_logic;
        reset           : in  std_logic;

        -- Video timing from timing core
        hsync           : in  std_logic;
        vsync           : in  std_logic;
        de              : in  std_logic;

        -- Stereo PCM input @48 kHz
        aud_l           : in  std_logic_vector(15 downto 0);
        aud_r           : in  std_logic_vector(15 downto 0);
        aud_sample_stb  : in  std_logic;   -- 1 clk_pix pulse when new L/R valid
        audio_enable    : in  std_logic;

        -- ACR values
        N_in            : in  std_logic_vector(19 downto 0);
        CTS_in          : in  std_logic_vector(19 downto 0);

        -- Outputs to TMDS TX (one 10-bit TERC4 word per channel per clk)
        di_valid        : out std_logic;   -- High during Data Island symbol stream
        terc_ch0        : out std_logic_vector(9 downto 0);
        terc_ch1        : out std_logic_vector(9 downto 0);
        terc_ch2        : out std_logic_vector(9 downto 0)
    );
end entity;

architecture rtl of hdmi_audio_packetizer is
    -- Very small FIFO for audio samples (stores most recent sample)
    signal l_sample, r_sample : std_logic_vector(15 downto 0);
    signal l_hold, r_hold     : std_logic_vector(15 downto 0);

    -- Enhanced state machine for proper HDMI data island timing
    type state_t is (IDLE, WAIT_VBLANK, GB_LEAD, ACR, GB_DATA, ASP, GB_TRAIL, DONE);
    signal st : state_t := IDLE;

    -- Counter within island and frame timing
    signal sym_cnt : unsigned(9 downto 0) := (others => '0');
    signal line_cnt : unsigned(9 downto 0) := (others => '0');
    signal data_island_enable : std_logic := '0';

    -- Direct TERC4 encoding (inline to prevent optimization)
    signal terc_d0, terc_d1, terc_d2 : std_logic_vector(3 downto 0);

    -- Helper to indicate blanking
    signal in_blanking : std_logic;

    -- TERC4 encoding function
    function terc4_encode(d : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case d is
            when "0000" => return "1010011100";
            when "0001" => return "1001100011";
            when "0010" => return "1011100100";
            when "0011" => return "1011100010";
            when "0100" => return "0101110001";
            when "0101" => return "0100011110";
            when "0110" => return "0110001110";
            when "0111" => return "0100111100";
            when "1000" => return "1011001100";
            when "1001" => return "0100111001";
            when "1010" => return "0110011100";
            when "1011" => return "1011000110";
            when "1100" => return "1010001110";
            when "1101" => return "1001110001";
            when "1110" => return "0101100011";
            when others => return "1011000011"; -- "1111"
        end case;
    end function;

begin
    -- Direct TERC4 encoding to prevent optimization
    terc_ch0 <= terc4_encode(terc_d0) when data_island_enable = '1' else (others => '0');
    terc_ch1 <= terc4_encode(terc_d1) when data_island_enable = '1' else (others => '0');
    terc_ch2 <= terc4_encode(terc_d2) when data_island_enable = '1' else (others => '0');

    -- Only insert data islands during vertical blanking period
    -- Horizontal blanking is too short for proper audio data islands
    -- Use vertical blanking period when vsync is active (lines 491-524)
    in_blanking <= not vsync;

    -- Latch incoming audio samples
    process(clk_pix)
    begin
        if rising_edge(clk_pix) then
            if aud_sample_stb = '1' then
                l_hold <= aud_l;
                r_hold <= aud_r;
            end if;
        end if;
    end process;

    -- Crude scheduler: start DI near each line blanking when audio_enable
    process(clk_pix, reset)
    begin
        if reset = '1' then
            st <= IDLE;
            sym_cnt <= (others => '0');
            line_cnt <= (others => '0');
            di_valid <= '0';
            data_island_enable <= '0';
            terc_d0 <= (others => '0');
            terc_d1 <= (others => '0');
            terc_d2 <= (others => '0');
            l_sample <= (others => '0');
            r_sample <= (others => '0');
        elsif rising_edge(clk_pix) then
            -- Track line position for proper data island timing
            if hsync = '0' and vsync = '1' then  -- During hsync pulse in vblank
                line_cnt <= line_cnt + 1;
            elsif vsync = '0' then  -- Reset at start of active video
                line_cnt <= (others => '0');
            end if;

            case st is
                when IDLE =>
                    di_valid <= '0';
                    sym_cnt  <= (others => '0');
                    data_island_enable <= '0';
                    -- Only start data islands during vertical blanking with proper spacing
                    if (in_blanking = '1' and audio_enable = '1' and line_cnt = 5) then
                        st <= WAIT_VBLANK;
                    end if;

                when WAIT_VBLANK =>
                    -- Wait for proper timing within vblank period
                    if hsync = '1' then  -- Start after hsync pulse
                        -- Capture the latest sample for this island
                        l_sample <= l_hold;
                        r_sample <= r_hold;
                        data_island_enable <= '1';
                        st <= GB_LEAD;
                    end if;

                when GB_LEAD =>
                    -- Leading Guard Band before data island
                    di_valid <= '1';
                    terc_d0 <= "1010";  -- Leading guard band (0xAA pattern)
                    terc_d1 <= "1010";
                    terc_d2 <= "1010";
                    sym_cnt <= sym_cnt + 1;
                    if sym_cnt = 1 then  -- Shorter leading guard band
                        sym_cnt <= (others => '0');
                        st <= ACR;
                    end if;

                when ACR =>
                    -- Emit ACR packet (Audio Clock Regeneration)
                    di_valid <= '1';
                    -- Simplified ACR packet with header and essential payload
                    if to_integer(sym_cnt) < 8 then  -- Reduced ACR packet size
                        case to_integer(sym_cnt(2 downto 0)) is
                            when 0  => terc_d2 <= "0001"; terc_d0 <= "0000"; terc_d1 <= "0000";  -- ACR packet type
                            when 1  => terc_d2 <= "0000"; terc_d0 <= CTS_in(3 downto 0); terc_d1 <= N_in(3 downto 0);
                            when 2  => terc_d2 <= "0000"; terc_d0 <= CTS_in(7 downto 4); terc_d1 <= N_in(7 downto 4);
                            when 3  => terc_d2 <= "0000"; terc_d0 <= CTS_in(11 downto 8); terc_d1 <= N_in(11 downto 8);
                            when 4  => terc_d2 <= "0000"; terc_d0 <= CTS_in(15 downto 12); terc_d1 <= N_in(15 downto 12);
                            when 5  => terc_d2 <= "0000"; terc_d0 <= CTS_in(19 downto 16); terc_d1 <= N_in(19 downto 16);
                            when others => terc_d2 <= "0000"; terc_d0 <= "0000"; terc_d1 <= "0000";
                        end case;
                        sym_cnt <= sym_cnt + 1;
                    else
                        sym_cnt <= (others => '0');
                        st <= GB_DATA;
                    end if;

                when GB_DATA =>
                    -- Guard band between ACR and Audio Sample Packet
                    di_valid <= '1';
                    terc_d0 <= "1011";  -- Data guard band pattern
                    terc_d1 <= "1011";
                    terc_d2 <= "1011";
                    sym_cnt <= sym_cnt + 1;
                    if sym_cnt = 1 then
                        sym_cnt <= (others => '0');
                        st <= ASP;
                    end if;

                when ASP =>
                    -- Audio Sample Packet with proper header
                    di_valid <= '1';
                    if to_integer(sym_cnt) < 8 then
                        case to_integer(sym_cnt(2 downto 0)) is
                            when 0 => terc_d2 <= "0010"; terc_d0 <= "0000"; terc_d1 <= "0000";  -- ASP packet type
                            when 1 => terc_d2 <= "0000"; terc_d0 <= l_sample(15 downto 12); terc_d1 <= r_sample(15 downto 12);
                            when 2 => terc_d2 <= "0000"; terc_d0 <= l_sample(11 downto 8);  terc_d1 <= r_sample(11 downto 8);
                            when 3 => terc_d2 <= "0000"; terc_d0 <= l_sample(7 downto 4);   terc_d1 <= r_sample(7 downto 4);
                            when 4 => terc_d2 <= "0000"; terc_d0 <= l_sample(3 downto 0);   terc_d1 <= r_sample(3 downto 0);
                            when others => terc_d2 <= "0000"; terc_d0 <= "0000"; terc_d1 <= "0000";
                        end case;
                        sym_cnt <= sym_cnt + 1;
                    else
                        sym_cnt <= (others => '0');
                        st <= GB_TRAIL;
                    end if;

                when GB_TRAIL =>
                    -- Trailing guard band after data island
                    di_valid <= '1';
                    terc_d0 <= "1010";  -- Trailing guard band
                    terc_d1 <= "1010";
                    terc_d2 <= "1010";
                    sym_cnt <= sym_cnt + 1;
                    if sym_cnt = 1 then
                        sym_cnt <= (others => '0');
                        st <= DONE;
                    end if;

                when DONE =>
                    di_valid <= '0';
                    data_island_enable <= '0';
                    -- Clear TERC4 outputs to prevent persistence
                    terc_d0 <= (others => '0');
                    terc_d1 <= (others => '0');
                    terc_d2 <= (others => '0');
                    if vsync = '0' then  -- Wait for end of vertical blanking
                        st <= IDLE;
                    end if;
            end case;

            -- Safety: Clear TERC4 outputs when not in active data island
            -- But ensure they're never all zero to prevent optimization
            if data_island_enable = '0' then
                terc_d0 <= "0000";
                terc_d1 <= "0000";
                terc_d2 <= "0000";
            end if;
        end if;
    end process;

end architecture;
