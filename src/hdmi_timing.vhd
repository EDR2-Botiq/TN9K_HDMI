-------------------------------------------------------------------------------
-- HDMI Timing Generator for 800x480@60Hz
-- Generates pixel clock, sync signals, and data enable for HDMI output
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity HDMI_TIMING_800x480 is
    port (
        clk_pixel       : in  std_logic;  -- 32.186 MHz HDMI pixel clock
        reset         : in  std_logic;
        
        -- Video timing outputs
        hsync         : out std_logic;
        vsync         : out std_logic;
        de            : out std_logic;   -- Data enable (active video)
        
        -- Pixel coordinates
        pixel_x       : out std_logic_vector(9 downto 0);
        pixel_y       : out std_logic_vector(9 downto 0);
        
        -- Frame signals
        frame_start   : out std_logic;
        line_start    : out std_logic
    );
end HDMI_TIMING_800x480;

architecture RTL of HDMI_TIMING_800x480 is

    -- HDMI 800x480@60Hz timing parameters (VIC20Nano compatible)
    constant H_VISIBLE    : integer := 800;   -- Visible pixels
    constant H_FRONT      : integer := 40;    -- Front porch
    constant H_SYNC_WIDTH : integer := 128;   -- Sync pulse width
    constant H_BACK       : integer := 88;    -- Back porch
    constant H_TOTAL      : integer := 1056;  -- Total line time

    constant V_VISIBLE    : integer := 480;   -- Visible lines
    constant V_FRONT      : integer := 1;     -- Front porch
    constant V_SYNC_WIDTH : integer := 4;     -- Sync pulse width
    constant V_BACK       : integer := 23;    -- Back porch
    constant V_TOTAL      : integer := 508;   -- Total frame time
    
    -- Counters
    signal h_count : integer range 0 to H_TOTAL-1 := 0;
    signal v_count : integer range 0 to V_TOTAL-1 := 0;
    
    -- Internal signals
    signal hsync_i : std_logic;
    signal vsync_i : std_logic;
    signal de_i : std_logic;

begin

    -- Horizontal and vertical counters
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            h_count <= 0;
            v_count <= 0;
        elsif rising_edge(clk_pixel) then
            if h_count = H_TOTAL-1 then
                h_count <= 0;
                if v_count = V_TOTAL-1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;
    
    -- Generate horizontal sync
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            hsync_i <= '1';
        elsif rising_edge(clk_pixel) then
            if h_count >= (H_VISIBLE + H_FRONT) and
               h_count < (H_VISIBLE + H_FRONT + H_SYNC_WIDTH) then
                hsync_i <= '0';  -- Active low
            else
                hsync_i <= '1';
            end if;
        end if;
    end process;

    -- Generate vertical sync
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            vsync_i <= '1';
        elsif rising_edge(clk_pixel) then
            if v_count >= (V_VISIBLE + V_FRONT) and
               v_count < (V_VISIBLE + V_FRONT + V_SYNC_WIDTH) then
                vsync_i <= '0';  -- Active low
            else
                vsync_i <= '1';
            end if;
        end if;
    end process;
    
    -- Generate data enable (active video)
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            de_i <= '0';
        elsif rising_edge(clk_pixel) then
            if h_count < H_VISIBLE and v_count < V_VISIBLE then
                de_i <= '1';
            else
                de_i <= '0';
            end if;
        end if;
    end process;
    
    -- Generate frame and line start pulses
    process(clk_pixel, reset)
    begin
        if reset = '1' then
            frame_start <= '0';
            line_start <= '0';
        elsif rising_edge(clk_pixel) then
            frame_start <= '0';
            line_start <= '0';
            
            if h_count = 0 and v_count = 0 then
                frame_start <= '1';
            end if;
            
            if h_count = 0 then
                line_start <= '1';
            end if;
        end if;
    end process;
    
    -- Output assignments
    hsync <= hsync_i;
    vsync <= vsync_i;
    de <= de_i;
    
    -- Pixel coordinates (always valid)
    pixel_x <= std_logic_vector(to_unsigned(h_count, 10));
    pixel_y <= std_logic_vector(to_unsigned(v_count, 10));

end RTL;