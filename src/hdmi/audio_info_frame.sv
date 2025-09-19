// Implementation of HDMI Audio InfoFrame.
// By Sameer Puri https://github.com/sameer

module audio_info_frame #(
    parameter logic[2:0] AUDIO_CHANNEL_COUNT = 3'b001, // 1 = 2 channels
    parameter logic[7:0] CHANNEL_ALLOCATION = 8'h00, // Channel allocation
    parameter logic[1:0] DOWN_MIX_INHIBITED = 2'b00, // Down-mix control
    parameter logic[2:0] LEVEL_SHIFT_VALUE = 3'b000 // Level shift value
) (
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

// Audio InfoFrame data
logic [7:0] packet_bytes [0:13];

always_comb
begin
    packet_bytes[0] = 8'h84; // Audio InfoFrame Type
    packet_bytes[1] = 8'h01; // Audio InfoFrame Version
    packet_bytes[2] = 8'h0A; // Audio InfoFrame Length (10 bytes)

    // Calculate checksum (256 - sum of all bytes)
    packet_bytes[3] = 8'd0; // Placeholder for checksum

    // Data Byte 1: Audio coding type, channel count
    packet_bytes[4] = {1'b0, 3'b000, 1'b0, AUDIO_CHANNEL_COUNT}; // CT=0 (refer to stream), CC=channel count

    // Data Byte 2: Sample frequency, sample size
    packet_bytes[5] = {3'b000, 2'b00, 3'b000}; // SF=0 (refer to stream), SS=0 (refer to stream)

    // Data Byte 3: Reserved
    packet_bytes[6] = 8'h00;

    // Data Byte 4: Channel allocation
    packet_bytes[7] = CHANNEL_ALLOCATION;

    // Data Byte 5: Down-mix control, level shift
    packet_bytes[8] = {3'b000, DOWN_MIX_INHIBITED, LEVEL_SHIFT_VALUE};

    // Data Bytes 6-10: Reserved
    packet_bytes[9] = 8'h00;
    packet_bytes[10] = 8'h00;
    packet_bytes[11] = 8'h00;
    packet_bytes[12] = 8'h00;
    packet_bytes[13] = 8'h00;
end

// Calculate checksum
logic [7:0] checksum;
always_comb
begin
    checksum = 8'd0;
    for (int i = 0; i < 14; i++)
    begin
        if (i != 3) // Skip checksum byte itself
            checksum += packet_bytes[i];
    end
    packet_bytes[3] = 8'd256 - checksum;
end

// Generate header
always_comb
begin
    header = {packet_bytes[2], packet_bytes[1], packet_bytes[0]};
end

// Generate subpackets
always_comb
begin
    sub[0] = {packet_bytes[10], packet_bytes[9], packet_bytes[8], packet_bytes[7], packet_bytes[6], packet_bytes[5], packet_bytes[4]};
    sub[1] = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, packet_bytes[11]};
    sub[2] = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, packet_bytes[13], packet_bytes[12]};
    sub[3] = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
end

endmodule