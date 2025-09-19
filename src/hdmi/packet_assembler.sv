// Implementation of HDMI packet ECC calculation and assembly.
// By Sameer Puri https://github.com/sameer

module packet_assembler(
    input logic clk_pixel,
    input logic reset,
    input logic data_island_period,
    input logic [23:0] header,
    input logic [55:0] sub [0:3],
    output logic [8:0] packet_data,
    output logic [4:0] counter
);

// 32 pixel wrap-around counter
logic [4:0] counter_int = 5'd0;
always_ff @(posedge clk_pixel)
begin
    if (reset)
        counter_int <= 5'd0;
    else if (data_island_period)
        counter_int <= counter_int + 1'd1;
end
assign counter = counter_int;

// Counter derivatives for 2-bit transfers
logic [5:0] counter_t2, counter_t2_p1;
assign counter_t2 = {counter_int, 1'b0};
assign counter_t2_p1 = {counter_int, 1'b1};

// Parity bits (initialized to 0)
logic [7:0] parity [0:4] = '{5{8'd0}};
logic [7:0] parity_next [0:4];
logic [7:0] parity_next_next [0:3];

// BCH data structures
logic [63:0] bch [0:3];
logic [31:0] bch4;

genvar i;
generate
    for (i = 0; i < 4; i++) begin : bch_gen
        assign bch[i] = {parity[i], sub[i]};
    end
endgenerate
assign bch4 = {parity[4], header};

// Packet data output assembly
always_comb
begin
    packet_data = {bch[3][counter_t2_p1], bch[2][counter_t2_p1], bch[1][counter_t2_p1], bch[0][counter_t2_p1],
                   bch[3][counter_t2], bch[2][counter_t2], bch[1][counter_t2], bch[0][counter_t2],
                   bch4[counter_int]};
end

// BCH Error Correction Code generator function
function logic [7:0] next_ecc(logic [7:0] ecc, logic next_bch_bit);
    if ((ecc[0] ^ next_bch_bit) == 1'b1)
        return ({1'b0, ecc[7:1]} ^ 8'h83);
    else
        return {1'b0, ecc[7:1]};
endfunction

// Parity calculation for blocks 0-3 (2 bits at a time)
generate
    for (i = 0; i < 4; i++) begin : parity_calc_2bit
        always_comb
        begin
            parity_next[i] = next_ecc(parity[i], sub[i][counter_t2]);
            parity_next_next[i] = next_ecc(parity_next[i], sub[i][counter_t2_p1]);
        end
    end
endgenerate

// Parity calculation for block 4 (header - 1 bit at a time)
always_comb
begin
    parity_next[4] = next_ecc(parity[4], header[counter_int]);
end

// Parity update process
always_ff @(posedge clk_pixel)
begin
    if (reset)
        parity <= '{5{8'd0}};
    else if (data_island_period)
    begin
        // Compute ECC only on subpacket data, not on itself
        if (counter_int < 28)
        begin
            parity[0:3] <= parity_next_next[0:3];
            // Header only has 24 bits, whereas subpackets have 56
            if (counter_int < 24)
                parity[4] <= parity_next[4];
        end
        else if (counter_int == 31)
        begin
            // Reset ECC for next packet
            parity <= '{5{8'd0}};
        end
    end
    else
        parity <= '{5{8'd0}};
end

endmodule