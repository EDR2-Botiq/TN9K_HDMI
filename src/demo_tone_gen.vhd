--------------------------------------------------------------------------------
-- Demo Tone Generator - Simple Audio Test Signal Generator
-- Generates test tones for HDMI audio demonstration
--
-- This module generates simple test tones that can be used to verify
-- HDMI audio functionality. It's separate from the pattern generator
-- to allow independent audio and video testing.
--
-- Features:
-- - Multiple tone patterns (sine approximation, square waves, etc.)
-- - Configurable tone frequency
-- - Stereo channel support with phase/frequency offset
-- - Audio enable control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity demo_tone_gen is
    port (
        -- Clock and reset
        clk_audio       : in  std_logic;  -- 48 kHz audio sample clock
        reset           : in  std_logic;  -- Reset (active high)

        -- Control inputs
        tone_enable     : in  std_logic;  -- Enable tone generation
        tone_select     : in  std_logic_vector(2 downto 0);  -- Select tone type

        -- Audio outputs
        audio_left      : out std_logic_vector(15 downto 0);  -- Left channel
        audio_right     : out std_logic_vector(15 downto 0);  -- Right channel
        audio_valid     : out std_logic   -- Audio data valid
    );
end demo_tone_gen;

architecture rtl of demo_tone_gen is

    -- Tone generation parameters
    constant SAMPLES_PER_CYCLE : integer := 48000 / 440;  -- 440 Hz tone

    -- Phase accumulator for tone generation
    signal phase_counter : unsigned(15 downto 0) := (others => '0');
    signal tone_amplitude : signed(15 downto 0);

    -- Sine wave lookup table (simplified)
    type sine_lut_t is array (0 to 63) of signed(15 downto 0);
    constant SINE_LUT : sine_lut_t := (
        x"0000", x"0C8C", x"18F9", x"2528", x"30FC", x"3C57", x"471D", x"5134",
        x"5A82", x"62F2", x"6A6E", x"70E3", x"7642", x"7A7D", x"7D8A", x"7F62",
        x"7FFF", x"7F62", x"7D8A", x"7A7D", x"7642", x"70E3", x"6A6E", x"62F2",
        x"5A82", x"5134", x"471D", x"3C57", x"30FC", x"2528", x"18F9", x"0C8C",
        x"0000", x"F374", x"E707", x"DAD8", x"CF04", x"C3A9", x"B8E3", x"AECC",
        x"A57E", x"9D0E", x"9592", x"8F1D", x"89BE", x"8583", x"8276", x"809E",
        x"8001", x"809E", x"8276", x"8583", x"89BE", x"8F1D", x"9592", x"9D0E",
        x"A57E", x"AECC", x"B8E3", x"C3A9", x"CF04", x"DAD8", x"E707", x"F374"
    );

begin

    -- Tone generation process
    process(clk_audio, reset)
    begin
        if reset = '1' then
            phase_counter <= (others => '0');
            tone_amplitude <= (others => '0');
            audio_left <= (others => '0');
            audio_right <= (others => '0');
            audio_valid <= '0';
        elsif rising_edge(clk_audio) then
            if tone_enable = '1' then
                -- Increment phase counter
                phase_counter <= phase_counter + 1;

                -- Generate tone based on selected pattern
                case tone_select is
                    when "000" =>  -- Sine wave (440 Hz)
                        tone_amplitude <= SINE_LUT(to_integer(phase_counter(15 downto 10)));
                        audio_left <= std_logic_vector(tone_amplitude);
                        audio_right <= std_logic_vector(tone_amplitude);

                    when "001" =>  -- Square wave
                        if phase_counter(15) = '0' then
                            audio_left <= x"4000";  -- +50% amplitude
                            audio_right <= x"4000";
                        else
                            audio_left <= x"C000";  -- -50% amplitude
                            audio_right <= x"C000";
                        end if;

                    when "010" =>  -- Stereo test (different frequencies)
                        -- Left channel: 440 Hz
                        audio_left <= std_logic_vector(SINE_LUT(to_integer(phase_counter(15 downto 10))));
                        -- Right channel: 880 Hz (double frequency)
                        audio_right <= std_logic_vector(SINE_LUT(to_integer(phase_counter(14 downto 9))));

                    when "011" =>  -- Sawtooth wave
                        audio_left <= std_logic_vector(signed(phase_counter) - 32768);
                        audio_right <= std_logic_vector(signed(phase_counter) - 32768);

                    when "100" =>  -- Pink noise (simplified)
                        -- Simple pseudo-random noise
                        audio_left <= std_logic_vector(signed(phase_counter(7 downto 0) & phase_counter(15 downto 8)));
                        audio_right <= std_logic_vector(signed(phase_counter(15 downto 8) & phase_counter(7 downto 0)));

                    when others => -- Silence
                        audio_left <= (others => '0');
                        audio_right <= (others => '0');
                end case;

                audio_valid <= '1';
            else
                -- Silence when disabled
                audio_left <= (others => '0');
                audio_right <= (others => '0');
                audio_valid <= '0';
            end if;
        end if;
    end process;

end rtl;