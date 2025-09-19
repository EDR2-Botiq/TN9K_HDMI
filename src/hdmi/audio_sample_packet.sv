// Implementation of HDMI audio sample packet.
// By Sameer Puri https://github.com/sameer

module audio_sample_packet #(
    parameter int AUDIO_BIT_WIDTH = 16,

    // IEC 60958-3 parameters
    parameter logic GRADE = 1'b0, // 0 = consumer, 1 = professional
    parameter logic SAMPLE_WORD_TYPE = 1'b0, // 0 = linear PCM, 1 = compressed
    parameter logic COPYRIGHT_NOT_ASSERTED = 1'b1, // 0 = copyrighted, 1 = not copyrighted
    parameter logic[2:0] PRE_EMPHASIS = 3'b000, // 000 = no pre-emphasis
    parameter logic[1:0] MODE = 2'b00, // only valid value
    parameter logic[7:0] CATEGORY_CODE = 8'b00000000, // general category
    parameter logic[3:0] SOURCE_NUMBER = 4'b0000, // do not take into account
    parameter logic[3:0] SAMPLING_FREQUENCY = 4'b0010, // 48 kHz
    parameter logic[1:0] CLOCK_ACCURACY = 2'b00, // level II
    parameter logic[3:0] WORD_LENGTH = 4'b0000, // depends on AUDIO_BIT_WIDTH
    parameter logic[3:0] ORIGINAL_SAMPLING_FREQUENCY = 4'b0000,
    parameter logic LAYOUT = 1'b0 // 0 = 2-channel layout, 1 = more than 2 channels
) (
    input logic [7:0] frame_counter,
    input logic [1:0] valid_bit,
    input logic [1:0] user_data_bit,
    input logic [23:0] audio_sample_word_left [0:3],
    input logic [23:0] audio_sample_word_right [0:3],
    input logic [3:0] audio_sample_word_present,
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

// Build channel status bits
logic [191:0] channel_status_left, channel_status_right;

always_comb
begin
    channel_status_left = 192'd0;
    channel_status_left[0] = GRADE;
    channel_status_left[1] = SAMPLE_WORD_TYPE;
    channel_status_left[2] = COPYRIGHT_NOT_ASSERTED;
    channel_status_left[5:3] = PRE_EMPHASIS;
    channel_status_left[7:6] = MODE;
    channel_status_left[15:8] = CATEGORY_CODE;
    channel_status_left[19:16] = SOURCE_NUMBER;
    channel_status_left[20] = 1'b0; // Left channel
    channel_status_left[23:21] = 3'b000;
    channel_status_left[27:24] = SAMPLING_FREQUENCY;
    channel_status_left[29:28] = CLOCK_ACCURACY;
    channel_status_left[33:32] = 2'b00; // reserved
    channel_status_left[37:34] = WORD_LENGTH;
    channel_status_left[41:38] = ORIGINAL_SAMPLING_FREQUENCY;

    channel_status_right = channel_status_left;
    channel_status_right[20] = 1'b1; // Right channel
end

// Parity calculation function
function automatic logic calculate_parity(
    logic channel_status_bit,
    logic user_data_bit,
    logic valid_bit,
    logic [23:0] audio_sample_word
);
    logic parity;
    integer i;
    begin
        parity = channel_status_bit ^ user_data_bit ^ valid_bit;
        for (i = 0; i < 24; i++)
            parity = parity ^ audio_sample_word[i];
        return parity;
    end
endfunction

// Generate header
logic [3:0] b_bit;
genvar i;
generate
    for (i = 0; i < 4; i++) begin : header_gen
        assign b_bit[i] = (frame_counter[7:0] == 8'b00000000) && audio_sample_word_present[i];
    end
endgenerate

always_comb
begin
    header[7:0] = 8'h02; // Audio Sample packet type
    header[11:8] = audio_sample_word_present;
    header[15:12] = {3'b000, LAYOUT};
    header[19:16] = 4'b0000;
    header[23:20] = b_bit;
end

// Generate subpackets
generate
    for (i = 0; i < 4; i++) begin : sub_gen
        logic [7:0] frame_index;
        logic parity_left, parity_right;

        assign frame_index = (frame_counter + i) % 192;

        always_comb
        begin
            parity_left = calculate_parity(
                channel_status_left[frame_index],
                user_data_bit[0],
                valid_bit[0],
                audio_sample_word_left[i]
            );

            parity_right = calculate_parity(
                channel_status_right[frame_index],
                user_data_bit[1],
                valid_bit[1],
                audio_sample_word_right[i]
            );
        end

        always_comb
        begin
            if (audio_sample_word_present[i])
            begin
                sub[i] = {
                    parity_right,
                    channel_status_right[frame_index],
                    user_data_bit[1],
                    valid_bit[1],
                    parity_left,
                    channel_status_left[frame_index],
                    user_data_bit[0],
                    valid_bit[0],
                    audio_sample_word_right[i],
                    audio_sample_word_left[i]
                };
            end
            else
            begin
                sub[i] = 56'd0;
            end
        end
    end
endgenerate

endmodule