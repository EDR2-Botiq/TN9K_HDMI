// Implementation of HDMI TMDS channel encoding.
// By Sameer Puri https://github.com/sameer

module tmds_channel #(
    parameter int CN = 0 // Channel number
) (
    input logic clk_pixel,
    input logic [7:0] video_data,
    input logic [1:0] data_island_data,
    input logic [1:0] control_data,
    input logic [1:0] mode, // {data_island_period, video_data_period}
    output logic [9:0] tmds
);

// TMDS encoding
logic [8:0] video_coding;
tmds_encoder tmds_encoder(.data_in(video_data), .disparity_in(disparity), .data_out(video_coding[7:0]), .disparity_out(video_coding[8]));

// Running disparity
logic [8:0] disparity = 9'sd0;
always_ff @(posedge clk_pixel)
begin
    case (mode)
        2'b01: disparity <= disparity + 9'(video_coding[8]);
        default: disparity <= 9'sd0;
    endcase
end

// Control codes
logic [9:0] control_coding;
always_comb
begin
    case (control_data)
        2'b00: control_coding = 10'b1101010100;
        2'b01: control_coding = 10'b0010101011;
        2'b10: control_coding = 10'b0101010100;
        2'b11: control_coding = 10'b1010101011;
    endcase
end

// Data island TERC4 encoding
logic [9:0] terc4_coding;
always_comb
begin
    case (data_island_data)
        4'h0: terc4_coding = 10'b1010011100;
        4'h1: terc4_coding = 10'b1001100011;
        4'h2: terc4_coding = 10'b1011100100;
        4'h3: terc4_coding = 10'b1011100010;
        4'h4: terc4_coding = 10'b0101110001;
        4'h5: terc4_coding = 10'b0100011110;
        4'h6: terc4_coding = 10'b0110001110;
        4'h7: terc4_coding = 10'b0100111100;
        4'h8: terc4_coding = 10'b1011001100;
        4'h9: terc4_coding = 10'b0100111001;
        4'hA: terc4_coding = 10'b0110011100;
        4'hB: terc4_coding = 10'b1011000110;
        4'hC: terc4_coding = 10'b1010001110;
        4'hD: terc4_coding = 10'b1001110001;
        4'hE: terc4_coding = 10'b0101100011;
        4'hF: terc4_coding = 10'b1011000011;
    endcase
end

// Guard bands
logic [9:0] video_guard_band, data_island_guard_band;
always_comb
begin
    case (CN)
        0:
        begin
            video_guard_band = 10'b1011001100;
            data_island_guard_band = 10'b0100110011;
        end
        1:
        begin
            video_guard_band = 10'b0100110011;
            data_island_guard_band = 10'b1011001100;
        end
        2:
        begin
            video_guard_band = 10'b1011001100;
            data_island_guard_band = 10'b1011001100;
        end
        default:
        begin
            video_guard_band = 10'b1011001100;
            data_island_guard_band = 10'b0100110011;
        end
    endcase
end

// Output selection based on mode
always_comb
begin
    case (mode)
        2'b00: tmds = control_coding;
        2'b01: tmds = {video_coding[8], video_coding[8], video_coding[7:0]};
        2'b10: tmds = terc4_coding;
        2'b11: tmds = data_island_guard_band;
        default: tmds = control_coding;
    endcase
end

endmodule

// TMDS Encoder submodule
module tmds_encoder(
    input logic [7:0] data_in,
    input logic [8:0] disparity_in,
    output logic [7:0] data_out,
    output logic disparity_out
);

logic [7:0] xor_encoded, xnor_encoded;
logic [7:0] encoded;
logic [3:0] ones_count;
logic use_xnor;

// Count ones in input data
always_comb
begin
    ones_count = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                 data_in[4] + data_in[5] + data_in[6] + data_in[7];
end

// XOR encoding
always_comb
begin
    xor_encoded[0] = data_in[0];
    xor_encoded[1] = data_in[1] ^ xor_encoded[0];
    xor_encoded[2] = data_in[2] ^ xor_encoded[1];
    xor_encoded[3] = data_in[3] ^ xor_encoded[2];
    xor_encoded[4] = data_in[4] ^ xor_encoded[3];
    xor_encoded[5] = data_in[5] ^ xor_encoded[4];
    xor_encoded[6] = data_in[6] ^ xor_encoded[5];
    xor_encoded[7] = data_in[7] ^ xor_encoded[6];
end

// XNOR encoding
always_comb
begin
    xnor_encoded[0] = data_in[0];
    xnor_encoded[1] = data_in[1] ~^ xnor_encoded[0];
    xnor_encoded[2] = data_in[2] ~^ xnor_encoded[1];
    xnor_encoded[3] = data_in[3] ~^ xnor_encoded[2];
    xnor_encoded[4] = data_in[4] ~^ xnor_encoded[3];
    xnor_encoded[5] = data_in[5] ~^ xnor_encoded[4];
    xnor_encoded[6] = data_in[6] ~^ xnor_encoded[5];
    xnor_encoded[7] = data_in[7] ~^ xnor_encoded[6];
end

// Choose encoding method
assign use_xnor = (ones_count > 4) || (ones_count == 4 && data_in[0] == 1'b0);
assign encoded = use_xnor ? xnor_encoded : xor_encoded;

// Calculate output disparity
logic [3:0] encoded_ones;
always_comb
begin
    encoded_ones = encoded[0] + encoded[1] + encoded[2] + encoded[3] +
                   encoded[4] + encoded[5] + encoded[6] + encoded[7];
end

// Final output logic
always_comb
begin
    if (disparity_in == 9'sd0 || encoded_ones == 4)
    begin
        data_out = {~use_xnor, use_xnor, encoded};
        if (use_xnor)
            disparity_out = 1'b1 - 2 * (encoded_ones == 4 ? 1'b0 : 1'b1);
        else
            disparity_out = 2 * (encoded_ones == 4 ? 1'b0 : 1'b1) - 1'b1;
    end
    else
    begin
        if ((disparity_in[8] == 1'b1 && encoded_ones > 4) ||
            (disparity_in[8] == 1'b0 && encoded_ones < 4))
        begin
            data_out = {1'b1, use_xnor, ~encoded};
            disparity_out = 2 * use_xnor + disparity_in[8:0] - 2 * encoded_ones;
        end
        else
        begin
            data_out = {1'b0, use_xnor, encoded};
            disparity_out = disparity_in[8:0] - 2 * use_xnor + 2 * encoded_ones - 8;
        end
    end
end

endmodule