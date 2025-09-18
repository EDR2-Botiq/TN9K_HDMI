--------------------------------------------------------------------------------
-- Demo Pattern Generator for HDMI Display
-- Generates 6 different test patterns at 640x480 resolution
-- Patterns automatically cycle every 5 seconds
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity demo_pattern_gen is
    port (
        clk_pixel       : in  std_logic;  -- 25.175 MHz pixel clock
        reset           : in  std_logic;  -- Active high reset
        
        -- Video timing inputs
        pixel_x         : in  std_logic_vector(9 downto 0);  -- Current X coordinate
        pixel_y         : in  std_logic_vector(9 downto 0);  -- Current Y coordinate
        video_active    : in  std_logic;  -- High during active video
        
        -- Pattern selection
        pattern_select  : in  std_logic_vector(2 downto 0);  -- Manual pattern selection
        auto_mode       : in  std_logic;  -- Enable automatic pattern cycling
        pixel_counter   : in  unsigned(31 downto 0);          -- Shared pixel counter
        
        -- RGB output
        rgb_out         : out std_logic_vector(23 downto 0);  -- 24-bit RGB output
        
        -- Status
        current_pattern : out std_logic_vector(2 downto 0)   -- Current pattern number
    );
end demo_pattern_gen;

architecture rtl of demo_pattern_gen is
    
    -- Constants for timing
    constant CLOCKS_PER_SEC : integer := 25175000;  -- 25.175 MHz
    constant PATTERN_DURATION : integer := 5;        -- 5 seconds per pattern
    constant CLOCKS_PER_PATTERN : integer := CLOCKS_PER_SEC * PATTERN_DURATION;
    
    -- Signals
    signal pattern_counter : unsigned(27 downto 0) := (others => '0');
    signal auto_pattern : unsigned(2 downto 0) := (others => '0');
    signal active_pattern : std_logic_vector(2 downto 0);
    signal x : unsigned(9 downto 0);
    signal y : unsigned(9 downto 0);
    
    -- Frame counter for moving patterns (derived from shared pixel_counter)
    signal frame_counter : unsigned(7 downto 0) := (others => '0');
    
    -- Color components
    signal red   : std_logic_vector(7 downto 0);
    signal green : std_logic_vector(7 downto 0);
    signal blue  : std_logic_vector(7 downto 0);
    
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
    
    -- Frame counter for moving patterns (using shared pixel_counter)
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            frame_counter <= (others => '0');
        elsif rising_edge(clk_pixel) then
            -- Increment frame counter every ~60th of a second using shared pixel_counter
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
                    
                    -- Pattern 0: Color Bars (Optimized with bit indexing)
                    when "000" =>
                        -- Use upper 3 bits of X for 8 bars (640/8 = 80px each)
                        case x(9 downto 7) is
                            when "000" => red <= x"FF"; green <= x"FF"; blue <= x"FF";  -- White
                            when "001" => red <= x"FF"; green <= x"FF"; blue <= x"00";  -- Yellow  
                            when "010" => red <= x"00"; green <= x"FF"; blue <= x"FF";  -- Cyan
                            when "011" => red <= x"00"; green <= x"FF"; blue <= x"00";  -- Green
                            when "100" => red <= x"FF"; green <= x"00"; blue <= x"FF";  -- Magenta
                            when "101" => red <= x"FF"; green <= x"00"; blue <= x"00";  -- Red
                            when "110" => red <= x"00"; green <= x"00"; blue <= x"FF";  -- Blue
                            when others => red <= x"00"; green <= x"00"; blue <= x"00";  -- Black
                        end case;
                    
                    -- Pattern 1: Checkerboard (Optimized - single XOR)
                    when "001" =>
                        -- 64x64 pixel squares using bit 6 for checkerboard pattern
                        if (x(6) xor y(6)) = '1' then
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
                        
                        -- Draw a 64x64 box
                        if (x >= x_block) and (x < x_block + 64) and 
                           (y >= y_block) and (y < y_block + 64) then
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
    
end rtl;