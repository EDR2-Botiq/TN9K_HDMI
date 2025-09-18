--------------------------------------------------------------------------------
-- Demo Pattern Generator with VIC20Nano-Compatible Audio
-- Generates 6 test patterns at 800x480 resolution with simple audio tone
--
-- VIC20NANO AUDIO APPROACH:
-- ========================
-- Simple single-tone audio generation for maximum stability and compatibility.
-- Uses constant 440 Hz tone output - matches VIC20Nano's minimal approach.
--
-- PATTERNS INCLUDED:
-- - Pattern 0 (Color Bars): Classic RGB color bar pattern
-- - Pattern 1 (Checkerboard): Black/white checkerboard pattern
-- - Pattern 2 (Gradient): Horizontal/vertical RGB gradients
-- - Pattern 3 (Grid): White grid on dark background
-- - Pattern 4 (Moving Box): Animated colored box
-- - Pattern 5 (Rainbow): Diagonal rainbow stripes
--
-- AUDIO IMPLEMENTATION (VIC20Nano Compatible):
-- - Simple 440 Hz square wave tone generation
-- - Phase accumulator for stable frequency output
-- - Stereo output with identical left/right channels
-- - Minimal complexity for maximum reliability
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_constants.all;

entity demo_pattern_gen is
    port (
        -- Clock inputs (from HDMI TX module)
        clk_pixel       : in  std_logic;  -- 25.175 MHz pixel clock
        clk_audio       : in  std_logic;  -- 48 kHz audio sample clock
        reset           : in  std_logic;  -- Active high reset

        -- Video timing inputs
        pixel_x         : in  std_logic_vector(9 downto 0);  -- Current X coordinate
        pixel_y         : in  std_logic_vector(9 downto 0);  -- Current Y coordinate
        video_active    : in  std_logic;  -- High during active video

        -- Pattern selection
        pattern_select  : in  std_logic_vector(2 downto 0);  -- Manual pattern selection
        auto_mode       : in  std_logic;  -- Enable automatic pattern cycling

        -- Audio control
        audio_enable_in : in  std_logic;  -- Audio enable control

        -- Video output
        rgb_out         : out std_logic_vector(23 downto 0);  -- 24-bit RGB output

        -- Audio output
        audio_left      : out std_logic_vector(15 downto 0);  -- Left audio channel
        audio_right     : out std_logic_vector(15 downto 0);  -- Right audio channel
        audio_enable    : out std_logic;  -- Enable audio embedding

        -- Status
        current_pattern : out std_logic_vector(2 downto 0)   -- Current pattern number
    );
end demo_pattern_gen;

architecture rtl of demo_pattern_gen is

    -- Constants for timing (using centralized constants)
    constant PATTERN_DURATION : integer := PATTERN_HOLD_TIME;  -- From hdmi_constants
    constant CLOCKS_PER_PATTERN : integer := CLOCKS_PER_SEC * PATTERN_DURATION;

    -- Video signals
    signal pattern_counter : unsigned(27 downto 0) := (others => '0');
    signal auto_pattern : unsigned(2 downto 0) := (others => '0');
    signal active_pattern : std_logic_vector(2 downto 0);
    signal x : unsigned(9 downto 0);
    signal y : unsigned(9 downto 0);
    signal frame_counter : unsigned(7 downto 0) := (others => '0');
    signal pixel_counter : unsigned(31 downto 0) := (others => '0');

    -- Color components
    signal red   : std_logic_vector(7 downto 0);
    signal green : std_logic_vector(7 downto 0);
    signal blue  : std_logic_vector(7 downto 0);

    -- Audio signals
    signal audio_phase_acc : unsigned(15 downto 0) := (others => '0');
    signal audio_amplitude : signed(15 downto 0);
    signal audio_freq_div  : unsigned(15 downto 0);



    
begin
    
    -- Convert inputs to unsigned for arithmetic
    x <= unsigned(pixel_x);
    y <= unsigned(pixel_y);
    
    -- Pattern selection: auto mode or manual
    active_pattern <= std_logic_vector(auto_pattern) when auto_mode = '1' else pattern_select;
    current_pattern <= active_pattern;
    
    -- Auto pattern cycling (5 seconds per pattern)
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            pattern_counter <= (others => '0');
            auto_pattern <= (others => '0');
        elsif rising_edge(clk_pixel) then
            if pattern_counter = CLOCKS_PER_PATTERN - 1 then
                pattern_counter <= (others => '0');
                -- Cycle through 6 patterns (0-5)
                if auto_pattern = 5 then
                    auto_pattern <= (others => '0');
                else
                    auto_pattern <= auto_pattern + 1;
                end if;
            else
                pattern_counter <= pattern_counter + 1;
            end if;
        end if;
    end process;
    
    -- Pixel and frame counters for animation
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            pixel_counter <= (others => '0');
            frame_counter <= (others => '0');
        elsif rising_edge(clk_pixel) then
            pixel_counter <= pixel_counter + 1;
            -- Increment frame counter every ~60th of a second
            if pixel_counter(19 downto 0) = 0 then  -- ~24 Hz animation
                frame_counter <= frame_counter + 1;
            end if;
        end if;
    end process;
    
    -- Pattern generation
    process(clk_pixel)
        variable x_block : unsigned(9 downto 0);
        variable y_block : unsigned(9 downto 0);
        variable diagonal : unsigned(10 downto 0);
    begin
        if rising_edge(clk_pixel) then
            if video_active = '1' then
                case active_pattern is
                    
                    -- Pattern 0: Color Bars (Fixed for 800x480)
                    when "000" =>
                        -- 8 bars: create index 0-7 based on x position for 800 pixels
                        if x < 100 then
                            red <= x"FF"; green <= x"FF"; blue <= x"FF";  -- White
                        elsif x < 200 then
                            red <= x"FF"; green <= x"FF"; blue <= x"00";  -- Yellow
                        elsif x < 300 then
                            red <= x"00"; green <= x"FF"; blue <= x"FF";  -- Cyan
                        elsif x < 400 then
                            red <= x"00"; green <= x"FF"; blue <= x"00";  -- Green
                        elsif x < 500 then
                            red <= x"FF"; green <= x"00"; blue <= x"FF";  -- Magenta
                        elsif x < 600 then
                            red <= x"FF"; green <= x"00"; blue <= x"00";  -- Red
                        elsif x < 700 then
                            red <= x"00"; green <= x"00"; blue <= x"FF";  -- Blue
                        else
                            red <= x"00"; green <= x"00"; blue <= x"00";  -- Black
                        end if;
                    
                    -- Pattern 1: Checkerboard (Optimized - single XOR)
                    when "001" =>
                        -- 100x100 pixel squares (800÷100=8 across, 480÷100=4.8 down)
                        -- Use bits 6:5 to create 4x4 pattern of 100x100 squares
                        if ((x(6) xor x(5)) xor (y(6) xor y(5))) = '1' then
                            red <= x"FF"; green <= x"FF"; blue <= x"FF";  -- White
                        else
                            red <= x"00"; green <= x"00"; blue <= x"00";  -- Black
                        end if;
                    
                    -- Pattern 2: Gradient (Horizontal RGB gradient)
                    when "010" =>
                        -- Red gradient horizontally
                        red <= std_logic_vector(x(9 downto 2));
                        -- Green gradient vertically
                        green <= std_logic_vector(y(8 downto 1));
                        -- Blue as combination
                        blue <= std_logic_vector(x(9 downto 2) xor y(8 downto 1));
                    
                    -- Pattern 3: Grid/Crosshatch
                    when "011" =>
                        -- Draw grid lines every 32 pixels
                        if (x(4 downto 0) = "00000") or (y(4 downto 0) = "00000") then
                            red <= x"FF"; green <= x"FF"; blue <= x"FF";  -- White grid
                        else
                            -- Background gradient
                            red <= x"20"; 
                            green <= x"20";
                            blue <= x"40";  -- Dark blue background
                        end if;
                    
                    -- Pattern 4: Moving Box (Animated)
                    when "100" =>
                        -- Calculate box position based on frame counter
                        x_block := resize(frame_counter & "00", 10);  -- Box X position
                        y_block := resize(frame_counter & "0", 10);   -- Box Y position
                        
                        -- Draw a 80x80 box (proportional to 800x480)
                        if (x >= x_block) and (x < x_block + 80) and 
                           (y >= y_block) and (y < y_block + 60) then
                            -- Box color changes with position
                            red <= std_logic_vector(frame_counter);
                            green <= std_logic_vector(255 - frame_counter);
                            blue <= x"80";
                        else
                            -- Background
                            red <= x"10";
                            green <= x"10";
                            blue <= x"20";
                        end if;
                    
                    -- Pattern 5: Diagonal Rainbow Stripes
                    when "101" =>
                        diagonal := ('0' & x) + ('0' & y);
                        -- Create diagonal stripes with rainbow colors
                        case diagonal(7 downto 5) is
                            when "000" => red <= x"FF"; green <= x"00"; blue <= x"00";  -- Red
                            when "001" => red <= x"FF"; green <= x"7F"; blue <= x"00";  -- Orange
                            when "010" => red <= x"FF"; green <= x"FF"; blue <= x"00";  -- Yellow
                            when "011" => red <= x"00"; green <= x"FF"; blue <= x"00";  -- Green
                            when "100" => red <= x"00"; green <= x"FF"; blue <= x"FF";  -- Cyan
                            when "101" => red <= x"00"; green <= x"00"; blue <= x"FF";  -- Blue
                            when "110" => red <= x"7F"; green <= x"00"; blue <= x"FF";  -- Purple
                            when others => red <= x"FF"; green <= x"00"; blue <= x"FF"; -- Magenta
                        end case;
                    
                    -- Default: White screen
                    when others =>
                        red <= x"FF";
                        green <= x"FF";
                        blue <= x"FF";
                        
                end case;
            else
                -- Blanking period - output black
                red <= x"00";
                green <= x"00";
                blue <= x"00";
            end if;
        end if;
    end process;
    
    -- Combine RGB components into 24-bit output
    rgb_out <= red & green & blue;

    ----------------------------------------------------------------------------
    -- VIC20NANO SIMPLIFIED AUDIO GENERATION
    ----------------------------------------------------------------------------
    -- Simple single-tone audio generator matching VIC20Nano's approach
    -- Uses constant 440 Hz tone for all patterns - much simpler and more stable

    -- Fixed 440 Hz audio generation (VIC20Nano standard)
    -- Frequency divider: 48000 / (2 * 440) = ~55 (x"0037")
    audio_freq_div <= x"0037";  -- 440 Hz tone (A4 musical reference)

    -- VIC20NANO SIMPLE PHASE ACCUMULATOR:
    -- Use pixel clock with audio sample enable for proper timing
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            audio_phase_acc <= (others => '0');
            audio_amplitude <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Audio sample enable from clk_audio rising edge
            if clk_audio = '1' then
                -- Simple phase accumulator
                audio_phase_acc <= audio_phase_acc + audio_freq_div;

                -- Square wave generation using MSB
                if audio_phase_acc(15) = '1' then
                    audio_amplitude <= x"4000";  -- +50% amplitude
                else
                    audio_amplitude <= x"C000";  -- -50% amplitude
                end if;
            end if;
        end if;
    end process;

    -- VIC20NANO AUDIO OUTPUT:
    -- Direct audio output without conditional logic (simpler)
    audio_left <= std_logic_vector(audio_amplitude);
    audio_right <= std_logic_vector(audio_amplitude);
    audio_enable <= audio_enable_in;

end rtl;