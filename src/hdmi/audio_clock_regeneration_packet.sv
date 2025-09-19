// Implementation of HDMI Audio Clock Regeneration packet.
// By Sameer Puri https://github.com/sameer

module audio_clock_regeneration_packet #(
    parameter real VIDEO_RATE = 25.2e6,
    parameter real AUDIO_RATE = 48e3
) (
    input logic [19:0] n,
    input logic [19:0] cts,
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

always_comb
begin
    header[7:0] = 8'h01; // Audio Clock Regeneration packet type
    header[23:8] = 16'd0; // Reserved bits
end

// All 4 subpackets are identical for ACR
always_comb
begin
    sub[0][19:0] = cts;
    sub[0][23:20] = 4'd0;
    sub[0][43:24] = n;
    sub[0][55:44] = 12'd0;

    sub[1] = sub[0];
    sub[2] = sub[0];
    sub[3] = sub[0];
end

endmodule