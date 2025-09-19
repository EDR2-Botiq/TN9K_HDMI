// Implementation of HDMI Spec v1.4a
// By Sameer Puri https://github.com/sameer

// Copyright (c) 2018 Sameer Puri
// Licensed under the terms of the MIT License (see LICENSE file for details)

module hdmi #(
    parameter int VIDEO_ID_CODE = 2,
    parameter logic[7:0] IT_CONTENT = 8'h00,
    parameter real VIDEO_REFRESH_RATE = 59.93,
    parameter int AUDIO_RATE = 48000,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter logic[8*8-1:0] VENDOR_NAME = {"Sameer", 8'd0, 8'd0, 8'd0},
    parameter logic[8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0}
) (
    input logic clk_pixel_x5,
    input logic clk_pixel,
    input logic clk_audio,
    input logic reset,

    // Video inputs
    input logic [23:0] rgb,
    input logic [15:0] audio_sample_word_left,
    input logic [15:0] audio_sample_word_right,

    // Audio config
    input logic audio_enable,

    // External sync inputs (for VIC20 timing)
    input logic external_sync_enable,
    input logic external_hsync,
    input logic external_vsync,
    input logic external_de,

    // HDMI outputs
    output logic [2:0] tmds_p,
    output logic [2:0] tmds_n,
    output logic tmds_clock_p,
    output logic tmds_clock_n,

    // Control and status
    output logic [10:0] cx,
    output logic [10:0] cy,
    output logic [10:0] screen_start_x,
    output logic [10:0] screen_start_y,
    output logic [10:0] screen_width,
    output logic [10:0] screen_height
);

localparam logic [10:0] VIDEO_ID_CODES[255:0] = '{
    8'h00: 11'd0,      // 0 - Reserved
    8'h01: 11'd640,    // 1 - 640x480p@59.94/60Hz
    8'h02: 11'd720,    // 2 - 720x480p@59.94/60Hz (NTSC)
    8'h03: 11'd720,    // 3 - 720x480p@59.94/60Hz (NTSC) 16:9
    8'h04: 11'd1280,   // 4 - 1280x720p@59.94/60Hz
    8'h05: 11'd1920,   // 5 - 1920x1080i@59.94/60Hz
    8'h06: 11'd720,    // 6 - 720(1440)x480i@59.94/60Hz
    8'h07: 11'd720,    // 7 - 720(1440)x480i@59.94/60Hz 16:9
    8'h08: 11'd720,    // 8 - 720(1440)x240p@59.94/60Hz
    8'h09: 11'd720,    // 9 - 720(1440)x240p@59.94/60Hz 16:9
    8'h0A: 11'd2880,   // 10 - 2880x480i@59.94/60Hz
    8'h0B: 11'd2880,   // 11 - 2880x480i@59.94/60Hz 16:9
    8'h0C: 11'd2880,   // 12 - 2880x240p@59.94/60Hz
    8'h0D: 11'd2880,   // 13 - 2880x240p@59.94/60Hz 16:9
    8'h0E: 11'd1440,   // 14 - 1440x480p@59.94/60Hz
    8'h0F: 11'd1440,   // 15 - 1440x480p@59.94/60Hz 16:9
    8'h10: 11'd1920,   // 16 - 1920x1080p@59.94/60Hz
    8'h11: 11'd720,    // 17 - 720x576p@50Hz (PAL)
    8'h12: 11'd720,    // 18 - 720x576p@50Hz (PAL) 16:9
    8'h13: 11'd1280,   // 19 - 1280x720p@50Hz
    8'h14: 11'd1920,   // 20 - 1920x1080i@50Hz
    8'h15: 11'd720,    // 21 - 720(1440)x576i@50Hz
    8'h16: 11'd720,    // 22 - 720(1440)x576i@50Hz 16:9
    8'h17: 11'd720,    // 23 - 720(1440)x288p@50Hz
    8'h18: 11'd720,    // 24 - 720(1440)x288p@50Hz 16:9
    8'h19: 11'd2880,   // 25 - 2880x576i@50Hz
    8'h1A: 11'd2880,   // 26 - 2880x576i@50Hz 16:9
    8'h1B: 11'd2880,   // 27 - 2880x288p@50Hz
    8'h1C: 11'd2880,   // 28 - 2880x288p@50Hz 16:9
    8'h1D: 11'd1440,   // 29 - 1440x576p@50Hz
    8'h1E: 11'd1440,   // 30 - 1440x576p@50Hz 16:9
    8'h1F: 11'd1920,   // 31 - 1920x1080p@50Hz
    default: 11'd800   // Default to 800 width for custom modes
};

localparam logic [10:0] VIDEO_ID_HEIGHTS[255:0] = '{
    8'h00: 11'd0,      // 0 - Reserved
    8'h01: 11'd480,    // 1 - 640x480p@59.94/60Hz
    8'h02: 11'd480,    // 2 - 720x480p@59.94/60Hz (NTSC)
    8'h03: 11'd480,    // 3 - 720x480p@59.94/60Hz (NTSC) 16:9
    8'h04: 11'd720,    // 4 - 1280x720p@59.94/60Hz
    8'h05: 11'd540,    // 5 - 1920x1080i@59.94/60Hz (interlaced, so 540 per field)
    8'h06: 11'd240,    // 6 - 720(1440)x480i@59.94/60Hz
    8'h07: 11'd240,    // 7 - 720(1440)x480i@59.94/60Hz 16:9
    8'h08: 11'd240,    // 8 - 720(1440)x240p@59.94/60Hz
    8'h09: 11'd240,    // 9 - 720(1440)x240p@59.94/60Hz 16:9
    8'h0A: 11'd240,    // 10 - 2880x480i@59.94/60Hz
    8'h0B: 11'd240,    // 11 - 2880x480i@59.94/60Hz 16:9
    8'h0C: 11'd240,    // 12 - 2880x240p@59.94/60Hz
    8'h0D: 11'd240,    // 13 - 2880x240p@59.94/60Hz 16:9
    8'h0E: 11'd480,    // 14 - 1440x480p@59.94/60Hz
    8'h0F: 11'd480,    // 15 - 1440x480p@59.94/60Hz 16:9
    8'h10: 11'd1080,   // 16 - 1920x1080p@59.94/60Hz
    8'h11: 11'd576,    // 17 - 720x576p@50Hz (PAL)
    8'h12: 11'd576,    // 18 - 720x576p@50Hz (PAL) 16:9
    8'h13: 11'd720,    // 19 - 1280x720p@50Hz
    8'h14: 11'd540,    // 20 - 1920x1080i@50Hz
    8'h15: 11'd288,    // 21 - 720(1440)x576i@50Hz
    8'h16: 11'd288,    // 22 - 720(1440)x576i@50Hz 16:9
    8'h17: 11'd288,    // 23 - 720(1440)x288p@50Hz
    8'h18: 11'd288,    // 24 - 720(1440)x288p@50Hz 16:9
    8'h19: 11'd288,    // 25 - 2880x576i@50Hz
    8'h1A: 11'd288,    // 26 - 2880x576i@50Hz 16:9
    8'h1B: 11'd288,    // 27 - 2880x288p@50Hz
    8'h1C: 11'd288,    // 28 - 2880x288p@50Hz 16:9
    8'h1D: 11'd576,    // 29 - 1440x576p@50Hz
    8'h1E: 11'd576,    // 30 - 1440x576p@50Hz 16:9
    8'h1F: 11'd1080,   // 31 - 1920x1080p@50Hz
    default: 11'd480   // Default to 480 height for custom modes
};

// Internal timing parameters for 800x480@60Hz (custom mode)
localparam logic [10:0] FRAME_WIDTH = 11'd1056;   // Total horizontal pixels
localparam logic [10:0] FRAME_HEIGHT = 11'd525;   // Total vertical lines
localparam logic [10:0] SCREEN_WIDTH = 11'd800;   // Active video width
localparam logic [10:0] SCREEN_HEIGHT = 11'd480;  // Active video height
localparam logic [10:0] HSYNC_PULSE_START = 11'd840;  // H-sync start
localparam logic [10:0] HSYNC_PULSE_SIZE = 11'd128;   // H-sync pulse width
localparam logic [10:0] VSYNC_PULSE_START = 11'd504;  // V-sync start
localparam logic [10:0] VSYNC_PULSE_SIZE = 11'd4;     // V-sync pulse width

assign screen_width = SCREEN_WIDTH;
assign screen_height = SCREEN_HEIGHT;
assign screen_start_x = 11'd0;
assign screen_start_y = 11'd0;

// Horizontal and vertical counters
always_ff @(posedge clk_pixel) begin
    if (reset) begin
        cx <= 11'd0;
        cy <= 11'd0;
    end else begin
        cx <= cx == FRAME_WIDTH - 1'b1 ? 11'd0 : cx + 1'b1;
        cy <= cx == FRAME_WIDTH - 1'b1 ? (cy == FRAME_HEIGHT - 1'b1 ? 11'd0 : cy + 1'b1) : cy;
    end
end

// Sync generation
logic hsync, vsync;
logic frame_start;

always_comb begin
    hsync = external_sync_enable ? external_hsync :
            (cx >= HSYNC_PULSE_START && cx < HSYNC_PULSE_START + HSYNC_PULSE_SIZE);
    vsync = external_sync_enable ? external_vsync :
            (cy >= VSYNC_PULSE_START && cy < VSYNC_PULSE_START + VSYNC_PULSE_SIZE);
    frame_start = cx == 11'd0 && cy == 11'd0;
end

// Data enable generation
logic de;
always_comb begin
    de = external_sync_enable ? external_de :
         (cx < SCREEN_WIDTH && cy < SCREEN_HEIGHT);
end

// Video control signals
logic video_data_period, video_guard, video_preamble;
always_comb begin
    video_data_period = de;
    video_guard = cx >= SCREEN_WIDTH && cx < SCREEN_WIDTH + 2;
    video_preamble = cx >= SCREEN_WIDTH + 2 && cx < SCREEN_WIDTH + 10;
end

// Data island periods (blanking intervals)
logic data_island_period, data_island_guard, data_island_preamble;
always_comb begin
    // Place data islands during horizontal blanking
    data_island_period = !video_data_period && !video_guard && !video_preamble &&
                        (cx >= SCREEN_WIDTH + 10) && (cx < FRAME_WIDTH - 10) &&
                        (cy < SCREEN_HEIGHT);
    data_island_guard = (cx >= SCREEN_WIDTH + 8 && cx < SCREEN_WIDTH + 10) ||
                       (cx >= FRAME_WIDTH - 10 && cx < FRAME_WIDTH - 8);
    data_island_preamble = (cx >= SCREEN_WIDTH + 6 && cx < SCREEN_WIDTH + 8) ||
                          (cx >= FRAME_WIDTH - 12 && cx < FRAME_WIDTH - 10);
end

// Packet generation
logic [23:0] header;
logic [55:0] sub [3:0];

packet_picker #(
    .VIDEO_ID_CODE(VIDEO_ID_CODE),
    .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
    .AUDIO_RATE(AUDIO_RATE),
    .VENDOR_NAME(VENDOR_NAME),
    .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
    .IT_CONTENT(IT_CONTENT)
) packet_picker_instance (
    .clk_pixel(clk_pixel),
    .clk_audio(clk_audio),
    .reset(reset),
    .video_field_end(frame_start),
    .packet_enable(data_island_period),
    .packet_pixel_counter(cx[4:0]),
    .audio_sample_word_left(audio_sample_word_left),
    .audio_sample_word_right(audio_sample_word_right),
    .header(header),
    .sub(sub)
);

// Packet assembler
logic [8:0] packet_data;
logic [4:0] packet_pixel_counter;

packet_assembler packet_assembler_instance (
    .clk_pixel(clk_pixel),
    .reset(reset),
    .data_island_period(data_island_period),
    .header(header),
    .sub(sub),
    .packet_data(packet_data),
    .counter(packet_pixel_counter)
);

// TMDS channels
logic [9:0] tmds_internal [0:2];

tmds_channel #(.CN(0)) tmds_channel_blue (
    .clk_pixel(clk_pixel),
    .video_data(rgb[7:0]),
    .data_island_data(packet_data[1:0]),
    .control_data({vsync, hsync}),
    .mode({data_island_period, video_data_period}),
    .tmds(tmds_internal[0])
);

tmds_channel #(.CN(1)) tmds_channel_green (
    .clk_pixel(clk_pixel),
    .video_data(rgb[15:8]),
    .data_island_data(packet_data[3:2]),
    .control_data(2'b00),
    .mode({data_island_period, video_data_period}),
    .tmds(tmds_internal[1])
);

tmds_channel #(.CN(2)) tmds_channel_red (
    .clk_pixel(clk_pixel),
    .video_data(rgb[23:16]),
    .data_island_data(packet_data[5:4]),
    .control_data(2'b00),
    .mode({data_island_period, video_data_period}),
    .tmds(tmds_internal[2])
);

// Serialization
serializer serializer_instance (
    .clk_pixel(clk_pixel),
    .clk_pixel_x5(clk_pixel_x5),
    .reset(reset),
    .tmds_internal(tmds_internal),
    .tmds_p(tmds_p),
    .tmds_n(tmds_n),
    .tmds_clock_p(tmds_clock_p),
    .tmds_clock_n(tmds_clock_n)
);

endmodule