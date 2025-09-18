-------------------------------------------------------------------------------
-- TMDS Encoder - Transition Minimized Differential Signaling
-- Used for HDMI/DVI encoding
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TMDS_ENCODER is
    generic (
        PIPELINE_BALANCE : boolean := false  -- When true, inserts an extra register between stages
    );
    port (
        clk     : in  std_logic;
        reset   : in  std_logic;
        data    : in  std_logic_vector(7 downto 0);
        c0      : in  std_logic;  -- Control bit 0 (hsync for blue channel)
        c1      : in  std_logic;  -- Control bit 1 (vsync for blue channel)
        de      : in  std_logic;  -- Data enable
        encoded : out std_logic_vector(9 downto 0)
    );
end TMDS_ENCODER;

architecture RTL of TMDS_ENCODER is

    -- Optimized: Use XOR tree for ones counting (parallel instead of loop)
    function count_ones(data : std_logic_vector(7 downto 0)) return unsigned is
    begin
        -- Parallel bit counting using adder tree
        return ("000" & data(7)) + ("000" & data(6)) + ("000" & data(5)) + ("000" & data(4)) +
               ("000" & data(3)) + ("000" & data(2)) + ("000" & data(1)) + ("000" & data(0));
    end function;
    
    -- Optimized: Use XOR tree (parallel instead of loop)
    function xor_reduce(data : std_logic_vector(7 downto 0)) return std_logic is
    begin
        -- Parallel XOR tree
        return data(7) xor data(6) xor data(5) xor data(4) xor 
               data(3) xor data(2) xor data(1) xor data(0);
    end function;
    
    signal dc_bias : signed(7 downto 0) := (others => '0');
    signal q_m : std_logic_vector(8 downto 0);
    signal q_m_reg : std_logic_vector(8 downto 0) := (others => '0');
    signal q_m_stage : std_logic_vector(8 downto 0);
    -- Optimized: Use unsigned instead of integer for better synthesis
    signal ones_count : unsigned(3 downto 0);  -- 0-8 needs 4 bits
    signal zeros_count : unsigned(3 downto 0); -- 0-8 needs 4 bits  
    signal q_out : std_logic_vector(9 downto 0);
    signal control_bits : std_logic_vector(1 downto 0);

begin

    -- Create control bits signal
    control_bits <= c1 & c0;

    -- Stage 1: Minimize transitions (Optimized - parallel logic)
    process(clk, reset)
        variable data_ones : unsigned(3 downto 0);
        variable use_xnor : std_logic;
    begin
        if reset = '1' then
            q_m <= (others => '0');
        elsif rising_edge(clk) then
            data_ones := count_ones(data);
            -- VHDL-93 compatible conditional assignment
            if (data_ones > "0100") or (data_ones = "0100" and data(0) = '0') then
                use_xnor := '1';
            else
                use_xnor := '0';
            end if;
            
            -- Parallel computation instead of loops
            q_m(0) <= data(0);
            if use_xnor = '1' then
                -- XNOR chain (parallel)
                q_m(1) <= data(0) xnor data(1);
                q_m(2) <= data(0) xnor data(1) xnor data(2);
                q_m(3) <= data(0) xnor data(1) xnor data(2) xnor data(3);
                q_m(4) <= data(0) xnor data(1) xnor data(2) xnor data(3) xnor data(4);
                q_m(5) <= data(0) xnor data(1) xnor data(2) xnor data(3) xnor data(4) xnor data(5);
                q_m(6) <= data(0) xnor data(1) xnor data(2) xnor data(3) xnor data(4) xnor data(5) xnor data(6);
                q_m(7) <= data(0) xnor data(1) xnor data(2) xnor data(3) xnor data(4) xnor data(5) xnor data(6) xnor data(7);
                q_m(8) <= '0';
            else
                -- XOR chain (parallel)  
                q_m(1) <= data(0) xor data(1);
                q_m(2) <= data(0) xor data(1) xor data(2);
                q_m(3) <= data(0) xor data(1) xor data(2) xor data(3);
                q_m(4) <= data(0) xor data(1) xor data(2) xor data(3) xor data(4);
                q_m(5) <= data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5);
                q_m(6) <= data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5) xor data(6);
                q_m(7) <= data(0) xor data(1) xor data(2) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7);
                q_m(8) <= '1';
            end if;
        end if;
    end process;
    
    -- Optional pipeline register between stage 1 and stage 2 for higher clock targets
    process(clk, reset)
    begin
        if reset = '1' then
            q_m_reg <= (others => '0');
        elsif rising_edge(clk) then
            if PIPELINE_BALANCE then
                q_m_reg <= q_m;
            end if;
        end if;
    end process;

    q_m_stage <= q_m when (not PIPELINE_BALANCE) else q_m_reg;

    -- Count ones and zeros in selected stage output
    ones_count <= count_ones(q_m_stage(7 downto 0));
    zeros_count <= "1000" - ones_count;  -- 8 as unsigned(3:0)
    
    -- Stage 2: DC balance (VHDL-93 compatible)
    process(clk, reset)
        variable bias_adjust : signed(7 downto 0);
    begin
        if reset = '1' then
            dc_bias <= (others => '0');
            q_out <= (others => '0');
        elsif rising_edge(clk) then
            if de = '0' then
                -- Control period
                dc_bias <= (others => '0');
                case control_bits is
                    when "00" => q_out <= "1101010100";
                    when "01" => q_out <= "0010101011";
                    when "10" => q_out <= "0101010100";
                    when "11" => q_out <= "1010101011";
                    when others => q_out <= "0000000000";
                end case;
            else
                -- Data period - simplified for VHDL-93
                -- Calculate bias adjustment using explicit type conversions
                if ones_count > zeros_count then
                    bias_adjust := "00000001";  -- +1
                elsif ones_count < zeros_count then
                    bias_adjust := "11111111";  -- -1
                else
                    bias_adjust := "00000000";  -- 0
                end if;
                
                if dc_bias = "00000000" or ones_count = "0100" then  -- 4 as unsigned
                    if q_m_stage(8) = '0' then
                        q_out(9) <= '1';
                        q_out(8) <= '0';
                        q_out(7 downto 0) <= not q_m_stage(7 downto 0);
                        dc_bias <= dc_bias - bias_adjust;
                    else
                        q_out(9) <= '0';
                        q_out(8) <= '1';
                        q_out(7 downto 0) <= q_m_stage(7 downto 0);
                        dc_bias <= dc_bias + bias_adjust;
                    end if;
                else
                    if (dc_bias > "00000000" and ones_count > "0100") or 
                       (dc_bias < "00000000" and ones_count < "0100") then
                        q_out(9) <= '1';
                        q_out(8) <= q_m_stage(8);
                        q_out(7 downto 0) <= not q_m_stage(7 downto 0);
                        dc_bias <= dc_bias - bias_adjust;
                    else
                        q_out(9) <= '0';
                        q_out(8) <= q_m_stage(8);
                        q_out(7 downto 0) <= q_m_stage(7 downto 0);
                        dc_bias <= dc_bias + bias_adjust;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    encoded <= q_out;

end RTL;