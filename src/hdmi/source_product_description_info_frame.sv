// Implementation of HDMI Source Product Description InfoFrame.
// By Sameer Puri https://github.com/sameer

module source_product_description_info_frame #(
    parameter logic[8*8-1:0] VENDOR_NAME = {"Sameer", 8'd0, 8'd0, 8'd0}, // 8 characters
    parameter logic[8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0}, // 16 characters
    parameter logic[7:0] SOURCE_DEVICE_INFORMATION = 8'h09 // 0x09 = PC general
) (
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

// SPD InfoFrame data
logic [7:0] packet_bytes [0:31];

// Extract vendor name
genvar i;
generate
    for (i = 0; i < 8; i++) begin : vendor_name_extract
        always_comb
        begin
            packet_bytes[4 + i] = VENDOR_NAME[8*(7-i) +: 8] == 8'd0 ? 8'h00 : VENDOR_NAME[8*(7-i) +: 8];
        end
    end
endgenerate

// Extract product description
generate
    for (i = 0; i < 16; i++) begin : product_desc_extract
        always_comb
        begin
            packet_bytes[12 + i] = PRODUCT_DESCRIPTION[8*(15-i) +: 8] == 8'd0 ? 8'h00 : PRODUCT_DESCRIPTION[8*(15-i) +: 8];
        end
    end
endgenerate

always_comb
begin
    packet_bytes[0] = 8'h83; // SPD InfoFrame Type
    packet_bytes[1] = 8'h01; // SPD InfoFrame Version
    packet_bytes[2] = 8'h19; // SPD InfoFrame Length (25 bytes)

    // Calculate checksum (256 - sum of all bytes)
    packet_bytes[3] = 8'd0; // Placeholder for checksum

    // Source Device Information
    packet_bytes[28] = SOURCE_DEVICE_INFORMATION;

    // Reserved bytes
    packet_bytes[29] = 8'h00;
    packet_bytes[30] = 8'h00;
    packet_bytes[31] = 8'h00;
end

// Calculate checksum
logic [7:0] checksum;
always_comb
begin
    checksum = 8'd0;
    for (int j = 0; j < 32; j++)
    begin
        if (j != 3) // Skip checksum byte itself
            checksum += packet_bytes[j];
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
    sub[3] = {packet_bytes[31], packet_bytes[30], packet_bytes[29], packet_bytes[28], packet_bytes[27], packet_bytes[26], packet_bytes[25]};
end

endmodule