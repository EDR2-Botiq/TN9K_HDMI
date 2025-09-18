--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.12 (64-bit)
--Part Number: GW1NR-LV9QN88PC6/I5
--Device: GW1NR-9
--Device Version: C
--Created Time: Thu Sep 18 21:38:47 2025

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component Gowin_HDMI_CLKDIV
    port (
        clkout: out std_logic;
        hclkin: in std_logic;
        resetn: in std_logic
    );
end component;

your_instance_name: Gowin_HDMI_CLKDIV
    port map (
        clkout => clkout,
        hclkin => hclkin,
        resetn => resetn
    );

----------Copy end-------------------
