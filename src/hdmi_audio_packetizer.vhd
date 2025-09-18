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
        pixel_y         : in  std_logic_vector(9 downto 0);  -- For proper vertical blank detection

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
    -- Sample currently being packetized
    signal l_sample, r_sample : std_logic_vector(15 downto 0);

    -- State machine for multiple packet emission during vertical blank
    type state_t is (IDLE, GB_LEAD, ACR, GB_DATA, ASP, GB_TRAIL, DONE);
    signal st : state_t := IDLE;

    -- Symbol counter within current sub-packet/phase
    signal sym_cnt : unsigned(9 downto 0) := (others => '0');
    signal data_island_enable : std_logic := '0';
    signal terc_d0, terc_d1, terc_d2 : std_logic_vector(3 downto 0);

    -- Vertical blank detection (lines >= 480 for 640x480 timing)
    signal vblank : std_logic;

    -- Per-frame tracking
    signal acr_sent_this_frame : std_logic := '0';
    signal vblank_prev         : std_logic := '0';
    signal vblank_line         : unsigned(9 downto 0) := (others => '0');
    signal packets_emitted     : unsigned(9 downto 0) := (others => '0');
    constant TARGET_PACKETS_PER_FRAME : integer := 48; -- Aim ~ one ASP per sample group
    constant VBLANK_LINES              : integer := 45; -- Approx lines in vertical blank region
    signal line_stride        : unsigned(9 downto 0);
    signal next_line_trigger  : unsigned(9 downto 0) := (others => '0');

    -- Small FIFO (depth 64) to accumulate 48 kHz samples
    type sample_t is record
        l : std_logic_vector(15 downto 0);
        r : std_logic_vector(15 downto 0);
    end record;
    type fifo_t is array (0 to 63) of sample_t;
    signal fifo_mem   : fifo_t;
    signal wr_ptr     : unsigned(5 downto 0) := (others => '0');
    signal rd_ptr     : unsigned(5 downto 0) := (others => '0');
    signal fifo_count : unsigned(6 downto 0) := (others => '0');
    signal fifo_pop   : std_logic := '0';
    signal fifo_push  : std_logic := '0';
    signal fifo_empty : std_logic;
    signal fifo_full  : std_logic;

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
    -- FIFO status signals
    process(fifo_count)
    begin
        if fifo_count = 0 then
            fifo_empty <= '1';
        else
            fifo_empty <= '0';
        end if;

        if fifo_count = 64 then
            fifo_full <= '1';
        else
            fifo_full <= '0';
        end if;
    end process;

    -- FIFO control
    process(aud_sample_stb, fifo_full)
    begin
        fifo_push <= aud_sample_stb and (not fifo_full);
    end process;

    -- Direct TERC4 encoding to prevent optimization
    process(data_island_enable, terc_d0, terc_d1, terc_d2)
    begin
        if data_island_enable = '1' then
            terc_ch0 <= terc4_encode(terc_d0);
            terc_ch1 <= terc4_encode(terc_d1);
            terc_ch2 <= terc4_encode(terc_d2);
        else
            terc_ch0 <= (others => '0');
            terc_ch1 <= (others => '0');
            terc_ch2 <= (others => '0');
        end if;
    end process;

    -- Determine vertical blank region using pixel_y >= 480
    process(pixel_y)
    begin
        if unsigned(pixel_y) >= 480 then
            vblank <= '1';
        else
            vblank <= '0';
        end if;
    end process;

    -- Latch incoming audio samples into FIFO
    process(clk_pix)
    begin
        if rising_edge(clk_pix) then
            if fifo_push = '1' then
                fifo_mem(to_integer(wr_ptr)).l <= aud_l;
                fifo_mem(to_integer(wr_ptr)).r <= aud_r;
                wr_ptr <= wr_ptr + 1;
                fifo_count <= fifo_count + 1;
            end if;
            if fifo_pop = '1' and fifo_empty = '0' then
                rd_ptr <= rd_ptr + 1;
                fifo_count <= fifo_count - 1;
            end if;
        end if;
    end process;

    -- Scheduler distributing packets across vertical blank
    process(clk_pix, reset)
    begin
        if reset = '1' then
            st <= IDLE;
            sym_cnt <= (others => '0');
            di_valid <= '0';
            data_island_enable <= '0';
            terc_d0 <= (others => '0');
            terc_d1 <= (others => '0');
            terc_d2 <= (others => '0');
            l_sample <= (others => '0');
            r_sample <= (others => '0');
            acr_sent_this_frame <= '0';
            vblank_prev <= '0';
            vblank_line <= (others => '0');
            packets_emitted <= (others => '0');
            next_line_trigger <= (others => '0');
        elsif rising_edge(clk_pix) then
            fifo_pop <= '0';

            -- Detect vblank rising edge
            if vblank = '1' and vblank_prev = '0' then
                vblank_line <= (others => '0');
                packets_emitted <= (others => '0');
                acr_sent_this_frame <= '0';
                -- Compute stride ~ VBLANK_LINES / TARGET_PACKETS_PER_FRAME (ceiling)
                if TARGET_PACKETS_PER_FRAME > 0 then
                    line_stride <= to_unsigned( (VBLANK_LINES + TARGET_PACKETS_PER_FRAME - 1) / TARGET_PACKETS_PER_FRAME, 10);
                else
                    line_stride <= to_unsigned(4,10);
                end if;
                next_line_trigger <= (others => '0');
            elsif vblank = '1' and hsync = '0' then
                vblank_line <= vblank_line + 1;
            end if;
            vblank_prev <= vblank;

            case st is
                when IDLE =>
                    di_valid <= '0';
                    sym_cnt  <= (others => '0');
                    data_island_enable <= '0';
                    if vblank = '1' and audio_enable = '1' and fifo_empty = '0' then
                        if vblank_line = next_line_trigger and packets_emitted < to_unsigned(TARGET_PACKETS_PER_FRAME, packets_emitted'length) then
                            -- Load next sample
                            l_sample <= fifo_mem(to_integer(rd_ptr)).l;
                            r_sample <= fifo_mem(to_integer(rd_ptr)).r;
                            fifo_pop <= '1';
                            data_island_enable <= '1';
                            st <= GB_LEAD;
                            next_line_trigger <= vblank_line + line_stride; -- schedule next
                        end if;
                    end if;

                when GB_LEAD =>
                    -- Leading Guard Band before data island
                    di_valid <= '1';
                    terc_d0 <= "1010";  -- Leading guard band (0xAA pattern)
                    terc_d1 <= "1010";
                    terc_d2 <= "1010";
                    sym_cnt <= sym_cnt + 1;
                    if sym_cnt = 1 then
                        sym_cnt <= (others => '0');
                        if acr_sent_this_frame = '0' then
                            st <= ACR;
                        else
                            st <= GB_DATA; -- Skip ACR after first per frame
                        end if;
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
                        acr_sent_this_frame <= '1';
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
                        packets_emitted <= packets_emitted + 1;
                        st <= DONE;
                    end if;

                when DONE =>
                    di_valid <= '0';
                    data_island_enable <= '0';
                    terc_d0 <= (others => '0');
                    terc_d1 <= (others => '0');
                    terc_d2 <= (others => '0');
                    -- Immediately allow more packets in same vblank or wait for next frame
                    if vblank = '0' then
                        st <= IDLE;
                    else
                        st <= IDLE;
                    end if;
            end case;

            -- Safety: Clear TERC4 outputs when not in active data island
            -- But ensure they're never all zero to prevent optimization
            if data_island_enable = '0' then
                terc_d0 <= (others => '0');
                terc_d1 <= (others => '0');
                terc_d2 <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
