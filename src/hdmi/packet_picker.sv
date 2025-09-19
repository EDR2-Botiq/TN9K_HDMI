// Implementation of HDMI packet choice logic.
// By Sameer Puri https://github.com/sameer

module packet_picker #(
    parameter int VIDEO_ID_CODE = 2,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter real AUDIO_RATE = 48000,
    parameter logic[8*8-1:0] VENDOR_NAME = {"Sameer", 8'd0, 8'd0, 8'd0},
    parameter logic[8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0},
    parameter logic[7:0] IT_CONTENT = 8'h00
) (
    input logic clk_pixel,
    input logic clk_audio,
    input logic reset,
    input logic video_field_end,
    input logic packet_enable,
    input logic [4:0] packet_pixel_counter,
    input logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word_left,
    input logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word_right,
    output logic [23:0] header,
    output logic [55:0] sub [0:3]
);

logic [23:0] headers [0:255];
logic [55:0] subs [0:255] [0:3];

logic audio_clock_regeneration_sent = 1'b0;
logic audio_info_frame_sent = 1'b0;
logic auxiliary_video_information_info_frame_sent = 1'b0;
logic source_product_description_info_frame_sent = 1'b0;

// NULL packet
always_comb
begin
    headers[8'h00] = 24'd0;
    subs[8'h00] = '{56'd0, 56'd0, 56'd0, 56'd0};
end

// Audio clock regeneration packet
logic [19:0] audio_clock_regeneration_n;
logic [19:0] audio_clock_regeneration_cts;
audio_clock_regeneration_packet audio_clock_regeneration_packet(.header(headers[8'h01]), .sub(subs[8'h01]), .n(audio_clock_regeneration_n), .cts(audio_clock_regeneration_cts));

// Audio sample packet
logic audio_sample_word_transfer_control = 1'b0;
logic [1:0] audio_sample_word_transfer_control_synchronizer_ff = 2'd0;
logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word_transfer_left, audio_sample_word_transfer_right;
logic sample_buffer_current = 1'b0;
logic sample_buffer_used = 1'b0;
logic sample_buffer_ready [0:1];
logic [23:0] audio_sample_word_buffer_left [0:1] [0:3];
logic [23:0] audio_sample_word_buffer_right [0:1] [0:3];
logic [1:0] samples_remaining = 2'd0;

always_ff @(posedge clk_audio)
begin
    audio_sample_word_transfer_control <= !audio_sample_word_transfer_control;
    audio_sample_word_transfer_left <= audio_sample_word_left;
    audio_sample_word_transfer_right <= audio_sample_word_right;
end

always_ff @(posedge clk_pixel)
begin
    audio_sample_word_transfer_control_synchronizer_ff <= {audio_sample_word_transfer_control, audio_sample_word_transfer_control_synchronizer_ff[1]};
    if (audio_sample_word_transfer_control_synchronizer_ff[1] ^ audio_sample_word_transfer_control_synchronizer_ff[0])
    begin
        if (!sample_buffer_ready[!sample_buffer_current])
        begin
            audio_sample_word_buffer_left[!sample_buffer_current][3 - samples_remaining] <= audio_sample_word_transfer_left;
            audio_sample_word_buffer_right[!sample_buffer_current][3 - samples_remaining] <= audio_sample_word_transfer_right;
            samples_remaining <= samples_remaining == 2'd0 ? 2'd3 : samples_remaining - 1'd1;
            sample_buffer_ready[!sample_buffer_current] <= samples_remaining == 2'd0;
        end
    end

    if (sample_buffer_used)
    begin
        sample_buffer_ready[sample_buffer_current] <= 1'b0;
        sample_buffer_current <= !sample_buffer_current;
        sample_buffer_used <= 1'b0;
    end
end

logic [7:0] frame_counter = 8'd0;
always_ff @(posedge clk_pixel)
begin
    if (reset)
        frame_counter <= 8'd0;
    else if (video_field_end)
        frame_counter <= frame_counter + 1'd1;
end

audio_sample_packet #(.AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH)) audio_sample_packet(
    .header(headers[8'h02]),
    .sub(subs[8'h02]),
    .frame_counter(frame_counter),
    .valid_bit(2'b00),
    .user_data_bit(2'b00),
    .audio_sample_word_left(audio_sample_word_buffer_left[sample_buffer_current]),
    .audio_sample_word_right(audio_sample_word_buffer_right[sample_buffer_current]),
    .audio_sample_word_present(4'b1111)
);

// AVI InfoFrame
auxiliary_video_information_info_frame #(.VIDEO_ID_CODE(VIDEO_ID_CODE), .IT_CONTENT(IT_CONTENT)) auxiliary_video_information_info_frame(.header(headers[8'h82]), .sub(subs[8'h82]));

// Audio InfoFrame
audio_info_frame audio_info_frame(.header(headers[8'h84]), .sub(subs[8'h84]));

// Source Product Description InfoFrame
source_product_description_info_frame #(.VENDOR_NAME(VENDOR_NAME), .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION)) source_product_description_info_frame(.header(headers[8'h83]), .sub(subs[8'h83]));

// Audio Clock Regeneration
localparam real AUDIO_CLOCK_REGENERATION_PACKET_RATE = AUDIO_RATE / 1000.0; // 1000 packets per second
localparam int AUDIO_CLOCK_REGENERATION_TICKS = int'(25200000.0 / AUDIO_CLOCK_REGENERATION_PACKET_RATE);
int audio_clock_regeneration_timer = AUDIO_CLOCK_REGENERATION_TICKS;

always_ff @(posedge clk_pixel)
begin
    if (reset)
    begin
        audio_clock_regeneration_timer <= AUDIO_CLOCK_REGENERATION_TICKS;
        audio_clock_regeneration_n <= 20'd6144; // 48kHz
        audio_clock_regeneration_cts <= 20'd25200;
    end
    else if (packet_enable && packet_pixel_counter == 5'd31)
    begin
        audio_clock_regeneration_timer <= audio_clock_regeneration_timer - 1'd1;
        if (audio_clock_regeneration_timer == 1)
        begin
            audio_clock_regeneration_timer <= AUDIO_CLOCK_REGENERATION_TICKS;
        end
    end
end

logic [7:0] packet_type;
always_comb
begin
    if (packet_pixel_counter == 5'd0)
    begin
        // Send packets in priority order
        if (audio_clock_regeneration_timer < 32 && !audio_clock_regeneration_sent)
            packet_type = 8'h01; // Audio Clock Regeneration
        else if (sample_buffer_ready[sample_buffer_current])
        begin
            packet_type = 8'h02; // Audio Sample
            sample_buffer_used = 1'b1;
        end
        else if (video_field_end && !audio_info_frame_sent)
            packet_type = 8'h84; // Audio InfoFrame
        else if (video_field_end && !auxiliary_video_information_info_frame_sent)
            packet_type = 8'h82; // AVI InfoFrame
        else if (video_field_end && !source_product_description_info_frame_sent)
            packet_type = 8'h83; // Source Product Description InfoFrame
        else
            packet_type = 8'h00; // NULL packet
    end
    else
        packet_type = 8'h00;
end

always_comb
begin
    header = headers[packet_type];
    sub = subs[packet_type];
end

// Track which InfoFrames have been sent this field
always_ff @(posedge clk_pixel)
begin
    if (reset || video_field_end)
    begin
        audio_clock_regeneration_sent <= 1'b0;
        audio_info_frame_sent <= 1'b0;
        auxiliary_video_information_info_frame_sent <= 1'b0;
        source_product_description_info_frame_sent <= 1'b0;
    end
    else if (packet_enable && packet_pixel_counter == 5'd31)
    begin
        case (packet_type)
            8'h01: audio_clock_regeneration_sent <= 1'b1;
            8'h84: audio_info_frame_sent <= 1'b1;
            8'h82: auxiliary_video_information_info_frame_sent <= 1'b1;
            8'h83: source_product_description_info_frame_sent <= 1'b1;
        endcase
    end
end

endmodule