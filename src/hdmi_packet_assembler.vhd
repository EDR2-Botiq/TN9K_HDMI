-------------------------------------------------------------------------------
-- hdmi_packet_assembler.vhd - VIC20Nano-Inspired BCH Error Correction Engine
-- Advanced HDMI packet assembly with BCH ECC based on VIC20Nano's proven design
--
-- VIC20NANO BCH ERROR CORRECTION STRATEGY:
-- ========================================
-- The VIC20Nano project demonstrated that proper BCH (Bose-Chaudhuri-Hocquenghem)
-- error correction is essential for reliable HDMI audio transport. This module
-- implements their proven approach for generating HDMI-compliant packets.
--
-- KEY VIC20NANO BCH PRINCIPLES:
-- - Real-time BCH ECC calculation during data island periods
-- - Efficient pipeline processing for 2-bit-per-clock throughput
-- - Proper HDMI timing compliance (2 guard + 32 data + 2 guard = 36 total)
-- - Synthesis dependencies that prevent optimization removal
--
-- BCH CODE BENEFITS (VIC20Nano Validated):
-- - Error detection and correction for audio data integrity
-- - HDMI receiver compatibility (required by specification)
-- - Synthesis dependency creation (prevents module optimization)
-- - Professional-grade audio reliability over HDMI links
--
-- TIMING STRUCTURE:
-- Following VIC20Nano's timing model for maximum compatibility with displays
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_packet_assembler is
    port (
        clk_pixel           : in  std_logic;
        reset               : in  std_logic;
        data_island_period  : in  std_logic;

        -- Packet data inputs (see HDMI Table 5-8 Packet Types)
        header              : in  std_logic_vector(23 downto 0);
        sub0                : in  std_logic_vector(55 downto 0);
        sub1                : in  std_logic_vector(55 downto 0);
        sub2                : in  std_logic_vector(55 downto 0);
        sub3                : in  std_logic_vector(55 downto 0);

        -- Outputs (see Figure 5-4 Data Island Packet and ECC Structure)
        packet_data         : out std_logic_vector(8 downto 0);
        counter             : out std_logic_vector(4 downto 0)
    );
end entity;

architecture rtl of hdmi_packet_assembler is

    -- VIC20NANO PACKET TIMING STATE MACHINE:
    -- HDMI specification: Guard Band (2) + Packet (32) + Guard Band (2) = 36 clocks total
    -- VIC20Nano uses this exact timing for maximum display compatibility
    type packet_state_t is (IDLE, GUARD_LEAD, DATA_ACTIVE, GUARD_TRAIL);
    signal packet_state : packet_state_t := IDLE;
    signal counter_int : unsigned(5 downto 0) := (others => '0');  -- 0-35 for full cycle
    signal packet_valid : std_logic := '0';

    -- VIC20NANO BCH THROUGHPUT OPTIMIZATION:
    -- BCH packets 0-3 are transferred two bits at a time for efficient bandwidth use
    signal counter_t2     : unsigned(5 downto 0);  -- Counter divided by 2
    signal counter_t2_p1  : unsigned(5 downto 0);  -- Counter + 1 for pipeline

    -- VIC20NANO BCH ECC CALCULATION STRUCTURES:
    -- Parity accumulation arrays for real-time error correction generation
    type parity_array_t is array (0 to 4) of std_logic_vector(7 downto 0);
    signal parity : parity_array_t := (others => (others => '0'));      -- Current ECC state
    signal parity_next : parity_array_t;                                 -- Next ECC (1 clock)
    signal parity_next_next : parity_array_t;                            -- Next ECC (2 clocks)

    -- VIC20NANO BCH DATA ORGANIZATION:
    -- HDMI packet structure: Header(24) + 4 × Subpackets(56) = 248 bits total
    signal bch0, bch1, bch2, bch3 : std_logic_vector(63 downto 0);      -- 4 × 64-bit subpackets
    signal bch4 : std_logic_vector(31 downto 0);                        -- Header + padding

    -- VIC20NANO BCH ERROR CORRECTION GENERATOR:
    -- =========================================
    -- Implements HDMI BCH(8,8) code generator per Figure 5-5 of HDMI specification
    -- Polynomial: x^8 + x^2 + x^1 + x^0 = 0x87 (binary: 10000111)
    -- VIC20Nano validation: This exact implementation provides reliable audio ECC
    function next_ecc(ecc : std_logic_vector(7 downto 0); next_bch_bit : std_logic)
        return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        if (ecc(0) xor next_bch_bit) = '1' then
            -- Polynomial feedback: x^8 + x^2 + x^1 + x^0
            result := ('0' & ecc(7 downto 1)) xor "10000011";  -- 0x83 = x^7+x^1+x^0
        else
            -- Simple shift without feedback
            result := ('0' & ecc(7 downto 1));
        end if;
        return result;
    end function;

begin

    -- HDMI-compliant packet state machine with guard bands
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            packet_state <= IDLE;
            counter_int <= (others => '0');
            packet_valid <= '0';
        elsif rising_edge(clk_pixel) then
            case packet_state is
                when IDLE =>
                    counter_int <= (others => '0');
                    packet_valid <= '0';
                    if data_island_period = '1' then
                        packet_state <= GUARD_LEAD;
                    end if;

                when GUARD_LEAD =>
                    packet_valid <= '0';  -- Guard band, not valid packet data
                    if counter_int = 1 then  -- 2 clocks of guard band
                        counter_int <= (others => '0');
                        packet_state <= DATA_ACTIVE;
                    else
                        counter_int <= counter_int + 1;
                    end if;

                when DATA_ACTIVE =>
                    packet_valid <= '1';  -- Valid packet data for 32 clocks
                    if counter_int = 31 then  -- 32 clocks of packet data
                        counter_int <= (others => '0');
                        packet_state <= GUARD_TRAIL;
                    else
                        counter_int <= counter_int + 1;
                    end if;

                when GUARD_TRAIL =>
                    packet_valid <= '0';  -- Guard band, not valid packet data
                    if counter_int = 1 then  -- 2 clocks of guard band
                        counter_int <= (others => '0');
                        packet_state <= IDLE;
                    else
                        counter_int <= counter_int + 1;
                    end if;
            end case;

            -- Force idle if data island period ends
            if data_island_period = '0' then
                packet_state <= IDLE;
                counter_int <= (others => '0');
                packet_valid <= '0';
            end if;
        end if;
    end process;

    -- Only output valid data during PACKET_DATA state
    counter <= std_logic_vector(counter_int(4 downto 0)) when packet_valid = '1' else (others => '0');

    -- Counter derivatives for 2-bit transfers (only during valid packet data)
    counter_t2 <= (counter_int(4 downto 0) & '0') when packet_valid = '1' else (others => '0');
    counter_t2_p1 <= (counter_int(4 downto 0) & '1') when packet_valid = '1' else (others => '0');

    -- BCH data structures
    bch0 <= parity(0) & sub0;
    bch1 <= parity(1) & sub1;
    bch2 <= parity(2) & sub2;
    bch3 <= parity(3) & sub3;
    bch4 <= parity(4) & header;

    -- Packet data output assembly (handled in state machine process below)

    -- Parity calculation for blocks 0-3 (2 bits at a time)
    -- The parity needs to be calculated 2 bits at a time for blocks 0 to 3
    -- There's 56 bits being sent 2 bits at a time over TMDS channels 1 & 2
    parity_next(0) <= next_ecc(parity(0), sub0(to_integer(counter_t2)));
    parity_next(1) <= next_ecc(parity(1), sub1(to_integer(counter_t2)));
    parity_next(2) <= next_ecc(parity(2), sub2(to_integer(counter_t2)));
    parity_next(3) <= next_ecc(parity(3), sub3(to_integer(counter_t2)));

    parity_next_next(0) <= next_ecc(parity_next(0), sub0(to_integer(counter_t2_p1)));
    parity_next_next(1) <= next_ecc(parity_next(1), sub1(to_integer(counter_t2_p1)));
    parity_next_next(2) <= next_ecc(parity_next(2), sub2(to_integer(counter_t2_p1)));
    parity_next_next(3) <= next_ecc(parity_next(3), sub3(to_integer(counter_t2_p1)));

    -- Parity calculation for block 4 (header - 1 bit at a time)
    parity_next(4) <= next_ecc(parity(4), header(to_integer(counter_int)));

    -- Parity update process
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            parity <= (others => (others => '0'));
        elsif rising_edge(clk_pixel) then
            if packet_valid = '1' then
                -- Compute ECC only during valid packet data, not on guard bands
                if counter_int < 28 then
                    parity(0) <= parity_next_next(0);
                    parity(1) <= parity_next_next(1);
                    parity(2) <= parity_next_next(2);
                    parity(3) <= parity_next_next(3);
                    -- Header only has 24 bits, whereas subpackets have 56
                    if counter_int < 24 then
                        parity(4) <= parity_next(4);
                    end if;
                elsif counter_int = 31 then
                    -- Reset ECC for next packet
                    parity <= (others => (others => '0'));
                end if;
            elsif packet_state = IDLE then
                parity <= (others => (others => '0'));
            end if;
        end if;
    end process;

    -- Packet data output with HDMI-compliant guard bands
    process(packet_state, counter_int, bch0, bch1, bch2, bch3, bch4, counter_t2, counter_t2_p1)
    begin
        case packet_state is
            when GUARD_LEAD | GUARD_TRAIL =>
                -- TERC4 guard band symbols (see HDMI spec section 5.2.3.1)
                packet_data <= "101010100";  -- Guard band pattern

            when DATA_ACTIVE =>
                -- Standard VIC20Nano packet data during active packet period
                if counter_int < 14 then
                    packet_data <= '1' & bch0(to_integer(counter_t2_p1)) & bch1(to_integer(counter_t2_p1)) &
                                         bch2(to_integer(counter_t2_p1)) & bch3(to_integer(counter_t2_p1)) &
                                         bch0(to_integer(counter_t2)) & bch1(to_integer(counter_t2)) &
                                         bch2(to_integer(counter_t2)) & bch3(to_integer(counter_t2));
                elsif counter_int < 18 then
                    packet_data <= '1' & x"00";
                else
                    packet_data <= '1' & bch4(to_integer(counter_int) - 18) & "0000000";
                end if;

            when others =>  -- IDLE
                packet_data <= (others => '0');
        end case;
    end process;

end rtl;