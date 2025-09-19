// Implementation of HDMI AVI InfoFrame.
// By Sameer Puri https://github.com/sameer

module auxiliary_video_information_info_frame #(
    parameter int VIDEO_ID_CODE = 2,
    parameter logic[1:0] RGB_OR_YCBCR = 2'b00, // 00 = RGB, 01 = YCbCr 4:2:2, 10 = YCbCr 4:4:4
    parameter logic[1:0] ACTIVE_FORMAT_ASPECT_RATIO = 2'b10, // 10 = 16:9
    parameter logic[1:0] PICTURE_ASPECT_RATIO = 2'b10, // 10 = 16:9
    parameter logic[1:0] COLORIMETRY = 2'b00, // 00 = no data
    parameter logic[1:0] SCALING = 2'b00, // 00 = no known scaling
    parameter logic[6:0] VIDEO_FORMAT = 7'h00, // CEA Short Video Descriptor
    parameter logic[1:0] QUANTIZATION_RANGE = 2'b00, // 00 = default
    parameter logic[2:0] EXTENDED_COLORIMETRY = 3'b000, // extended colorimetry info
    parameter logic[7:0] IT_CONTENT = 8'h00, // IT content and additional colorimetry
    parameter logic[3:0] PIXEL_REPETITION = 4'h0, // 0 = no repetition
    parameter logic[5:0] CONTENT_TYPE = 6'h00, // content type
    parameter logic[3:0] YCC_QUANTIZATION_RANGE = 4'h0, // YCC quantization range
    parameter logic[15:0] TOP_BAR = 16'h0000,
    parameter logic[15:0] BOTTOM_BAR = 16'h0000,
    parameter logic[15:0] LEFT_BAR = 16'h0000,
    parameter logic[15:0] RIGHT_BAR = 16'h0000
) (
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

// AVI InfoFrame data
logic [7:0] packet_bytes [0:27];

always_comb
begin
    packet_bytes[0] = 8'h82; // AVI InfoFrame Type
    packet_bytes[1] = 8'h02; // AVI InfoFrame Version
    packet_bytes[2] = 8'h0D; // AVI InfoFrame Length (13 bytes)

    // Calculate checksum (256 - sum of all bytes)
    packet_bytes[3] = 8'd0; // Placeholder for checksum

    // Data Byte 1
    packet_bytes[4] = {RGB_OR_YCBCR, ACTIVE_FORMAT_ASPECT_RATIO, 2'b00, PICTURE_ASPECT_RATIO};

    // Data Byte 2
    packet_bytes[5] = {COLORIMETRY, PICTURE_ASPECT_RATIO, SCALING, 2'b00};

    // Data Byte 3
    packet_bytes[6] = {1'b0, QUANTIZATION_RANGE, EXTENDED_COLORIMETRY, IT_CONTENT[1:0]};

    // Data Byte 4
    packet_bytes[7] = VIDEO_ID_CODE[6:0];

    // Data Byte 5
    packet_bytes[8] = {YCC_QUANTIZATION_RANGE, CONTENT_TYPE[1:0], PIXEL_REPETITION};

    // Data Bytes 6-7: Top Bar
    packet_bytes[9] = TOP_BAR[7:0];
    packet_bytes[10] = TOP_BAR[15:8];

    // Data Bytes 8-9: Bottom Bar
    packet_bytes[11] = BOTTOM_BAR[7:0];
    packet_bytes[12] = BOTTOM_BAR[15:8];

    // Data Bytes 10-11: Left Bar
    packet_bytes[13] = LEFT_BAR[7:0];
    packet_bytes[14] = LEFT_BAR[15:8];

    // Data Bytes 12-13: Right Bar
    packet_bytes[15] = RIGHT_BAR[7:0];
    packet_bytes[16] = RIGHT_BAR[15:8];

    // Remaining bytes are reserved
    packet_bytes[17] = 8'h00;
    packet_bytes[18] = 8'h00;
    packet_bytes[19] = 8'h00;
    packet_bytes[20] = 8'h00;
    packet_bytes[21] = 8'h00;
    packet_bytes[22] = 8'h00;
    packet_bytes[23] = 8'h00;
    packet_bytes[24] = 8'h00;
    packet_bytes[25] = 8'h00;
    packet_bytes[26] = 8'h00;
    packet_bytes[27] = 8'h00;
end

// Calculate checksum
logic [7:0] checksum;
always_comb
begin
    checksum = 8'd0;
    for (int i = 0; i < 28; i++)
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
    sub[1] = {packet_bytes[17], packet_bytes[16], packet_bytes[15], packet_bytes[14], packet_bytes[13], packet_bytes[12], packet_bytes[11]};
    sub[2] = {packet_bytes[24], packet_bytes[23], packet_bytes[22], packet_bytes[21], packet_bytes[20], packet_bytes[19], packet_bytes[18]};
    sub[3] = {packet_bytes[27], packet_bytes[26], packet_bytes[25], 8'h00, 8'h00, 8'h00, 8'h00};
end

endmodule