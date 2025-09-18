-------------------------------------------------------------------------------
-- hdmi_audio_acr.vhd
-- Generates ACR packet fields (N and CTS) for 48 kHz audio at either
-- 25.175 MHz or 25.200 MHz TMDS clock. Select by generics.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_audio_acr is
    generic (
        TMDS_CLK_25_175 : boolean := true   -- if false, uses 25.200 MHz
    );
    port (
        clk_pix  : in  std_logic;
        reset    : in  std_logic;
        -- Outputs for ACR packet
        N        : out std_logic_vector(19 downto 0);  -- 20-bit
        CTS      : out std_logic_vector(19 downto 0)   -- 20-bit
    );
end entity;

architecture rtl of hdmi_audio_acr is
    signal n_reg   : std_logic_vector(19 downto 0);
    signal cts_reg : std_logic_vector(19 downto 0);
begin
    -- Assign constant values based on generic
    process(clk_pix, reset)
    begin
        if reset = '1' then
            n_reg   <= (others => '0');
            cts_reg <= (others => '0');
        elsif rising_edge(clk_pix) then
            if TMDS_CLK_25_175 then
                n_reg   <= std_logic_vector(to_unsigned(6144, 20));
                cts_reg <= std_logic_vector(to_unsigned(25175, 20));
            else
                n_reg   <= std_logic_vector(to_unsigned(6144, 20));
                cts_reg <= std_logic_vector(to_unsigned(25200, 20));
            end if;
        end if;
    end process;

    -- Output assignments
    N   <= n_reg;
    CTS <= cts_reg;

end architecture;
