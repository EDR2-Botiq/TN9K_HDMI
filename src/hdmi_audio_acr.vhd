-------------------------------------------------------------------------------
-- hdmi_audio_acr.vhd
-- Generates ACR packet fields (N and CTS) for 48 kHz audio at
-- 32.186 MHz TMDS clock for 800x480@60Hz resolution.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_constants.all;

entity hdmi_audio_acr is
    generic (
        TMDS_CLK_25_175 : boolean := false   -- Uses 32.186 MHz for 800x480
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
                n_reg   <= ACR_N_VECTOR;   -- 6144 for 48kHz
                cts_reg <= std_logic_vector(to_unsigned(25175, 20));
            else
                -- VIC20Nano-compatible 800x480@60Hz timing
                n_reg   <= ACR_N_VECTOR;   -- 6144 for 48kHz (standard)
                cts_reg <= ACR_CTS_VECTOR; -- 32400 for actual 32.4MHz pixel clock
            end if;
        end if;
    end process;

    -- Output assignments
    N   <= n_reg;
    CTS <= cts_reg;

end architecture;
