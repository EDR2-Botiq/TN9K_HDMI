-------------------------------------------------------------------------------
-- hdmi_terc4.vhd
-- Minimal TERC4 encoder for HDMI data islands (4-bit symbol -> 10-bit)
-- Table per HDMI spec. Only 0..15 used for Data Island and Guard Bands.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity hdmi_terc4 is
    port (
        d    : in  std_logic_vector(3 downto 0);
        q    : out std_logic_vector(9 downto 0)
    );
end entity;

architecture rtl of hdmi_terc4 is
    -- Synthesis attributes to prevent optimization
    attribute keep : string;
    attribute keep of q : signal is "true";
    attribute syn_keep : string;
    attribute syn_keep of q : signal is "true";
begin
    process(d)
    begin
        case d is
            when "0000" => q <= "1010011100";
            when "0001" => q <= "1001100011";
            when "0010" => q <= "1011100100";
            when "0011" => q <= "1011100010";
            when "0100" => q <= "0101110001";
            when "0101" => q <= "0100011110";
            when "0110" => q <= "0110001110";
            when "0111" => q <= "0100111100";
            when "1000" => q <= "1011001100";
            when "1001" => q <= "0100111001";
            when "1010" => q <= "0110011100";
            when "1011" => q <= "1011000110";
            when "1100" => q <= "1010001110";
            when "1101" => q <= "1001110001";
            when "1110" => q <= "0101100011";
            when others => q <= "1011000011"; -- "1111"
        end case;
    end process;
end architecture;
