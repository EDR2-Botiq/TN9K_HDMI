--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.11.03 Education
--Part Number: GW1NR-LV9QN88PC6/I5
--Device: GW1NR-9
--Device Version: C
--Created Time: Fri Sep 19 11:39:56 2025

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component Gowin_TMDS_rPLL
    port (
        clkout: out std_logic;
        lock: out std_logic;
        clkin: in std_logic
    );
end component;

your_instance_name: Gowin_TMDS_rPLL
    port map (
        clkout => clkout,
        lock => lock,
        clkin => clkin
    );

----------Copy end-------------------
