`timescale 1ns / 1ps

module top (
    input  wire        clk100mhz,

    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_d,

    output wire        cam_xclk,
    inout  wire        cam_scl,
    inout  wire        cam_sda,
    output wire        cam_scl_pup,
    output wire        cam_sda_pup,
    output wire        cam_reset,
    output wire        cam_pwdn,

    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,

    output wire [3:0]  led
);

    // ========================================================
    // 1) 25 MHz pixel / accelerator clock and reset
    // ========================================================
    wire pix_clk;
    wire clock_locked;
    wire reset_n;

    clock_25mhz u_clock (
        .clk100mhz(clk100mhz),
        .clk25mhz(pix_clk),
        .locked(clock_locked)
    );

    power_on_reset #(
        .HOLD_CYCLES(2_000_000)
    ) u_reset (
        .clk(clk100mhz),
        .clock_locked(clock_locked),
        .reset_n(reset_n)
    );

    assign cam_xclk  = pix_clk;
    assign cam_reset = reset_n;
    assign cam_pwdn  = 1'b0;

    // Arty ChipKit-I2C physical pull-up resistor enables.
    assign cam_scl_pup = 1'b1;
    assign cam_sda_pup = 1'b1;

    // ========================================================
    // 2) OV7670 SCCB initialization
    // ========================================================
    wire scl_drive_low;
    wire sda_drive_low;
    wire cam_init_done;

    ov7670_init u_ov7670_init (
        .clk(clk100mhz),
        .reset_n(reset_n),
        .scl_drive_low(scl_drive_low),
        .sda_drive_low(sda_drive_low),
        .init_done(cam_init_done)
    );

    assign cam_scl = scl_drive_low ? 1'b0 : 1'bz;
    assign cam_sda = sda_drive_low ? 1'b0 : 1'bz;

    // ========================================================
    // 3) Camera capture and 320x240 grayscale framebuffer
    // ========================================================
    localparam integer FRAME_SIZE = 320 * 240;
    localparam integer FB_ADDR_W  = 17;

    wire [FB_ADDR_W-1:0] fb_wr_addr;
    wire                 fb_wr_en;
    wire [15:0]          fb_wr_data;

    wire [7:0] y_full_pix;
    wire       y_full_valid;
    wire [9:0] x_full;
    wire [9:0] y_full;

    cam_capture_gray_rgb565_320x240 u_capture (
        .pclk(cam_pclk),
        .reset_n(reset_n),
        .vsync(cam_vsync),
        .href(cam_href),
        .d(cam_d),
        .wr_addr(fb_wr_addr),
        .wr_en(fb_wr_en),
        .wr_data(fb_wr_data),
        .y_full_pix(y_full_pix),
        .y_full_valid(y_full_valid),
        .x_full(x_full),
        .y_full(y_full)
    );

    wire [FB_ADDR_W-1:0] fb_rd_addr;
    wire [15:0] fb_rd_data;

    frame_buffer_rgb565 #(
        .ADDR_WIDTH(FB_ADDR_W),
        .FRAME_SIZE(FRAME_SIZE)
    ) u_frame_buffer (
        .wr_clk(cam_pclk),
        .wr_en(fb_wr_en),
        .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data),
        .rd_clk(pix_clk),
        .rd_addr(fb_rd_addr),
        .rd_data(fb_rd_data)
    );

    // ========================================================
    // 4) VGA timing and 2x display scaling (320x240 -> 640x480)
    // ========================================================
    wire video_active;
    wire [9:0] vga_x;
    wire [9:0] vga_y;

    vga_640x480 u_vga (
        .clk(pix_clk),
        .reset_n(reset_n),
        .hs(vga_hs),
        .vs(vga_vs),
        .active(video_active),
        .x(vga_x),
        .y(vga_y)
    );

    wire [8:0] src_x = vga_x[9:1];
    wire [8:0] src_y = vga_y[9:1];

    // Combinational address into the synchronous framebuffer gives exactly
    // one clock of display latency, matching vga_x_d/vga_y_d below.
    assign fb_rd_addr = video_active
        ? ((src_y * 17'd320) + src_x)
        : {FB_ADDR_W{1'b0}};

    // ========================================================
    // 5) Whole-frame 64x64 grayscale model-input memory
    // ========================================================
    wire        gray_wr_en;
    wire [11:0] gray_wr_addr;
    wire [7:0]  gray_wr_data;
    wire        gray_frame_toggle;

    resize_whole_640x480_to_64x64 u_resize (
        .pclk(cam_pclk),
        .reset_n(reset_n),
        .vsync(cam_vsync),
        .pix_valid(y_full_valid),
        .x_full(x_full),
        .y_full(y_full),
        .y_in(y_full_pix),
        .wr_en(gray_wr_en),
        .wr_addr(gray_wr_addr),
        .wr_data(gray_wr_data),
        .frame_toggle(gray_frame_toggle)
    );

    // Synchronize the completed-frame toggle into pix_clk.
    reg gray_toggle_meta = 1'b0;
    reg gray_toggle_sync = 1'b0;
    reg gray_toggle_prev = 1'b0;

    always @(posedge pix_clk or negedge reset_n) begin
        if (!reset_n) begin
            gray_toggle_meta <= 1'b0;
            gray_toggle_sync <= 1'b0;
            gray_toggle_prev <= 1'b0;
        end else begin
            gray_toggle_meta <= gray_frame_toggle;
            gray_toggle_sync <= gray_toggle_meta;
            gray_toggle_prev <= gray_toggle_sync;
        end
    end

    wire new_gray_frame = gray_toggle_sync ^ gray_toggle_prev;

    // ========================================================
    // 6) Copy one complete 64x64 frame into the accelerator
    // ========================================================
    localparam [2:0]
        LOAD_IDLE    = 3'd0,
        LOAD_REQUEST = 3'd1,
        LOAD_WRITE   = 3'd2,
        LOAD_START   = 3'd3,
        LOAD_WAIT    = 3'd4;

    reg [2:0] loader_state = LOAD_IDLE;
    reg [11:0] loader_addr = 12'd0;

    wire loader_owns_gray =
        (loader_state == LOAD_REQUEST) ||
        (loader_state == LOAD_WRITE);

    // Top-left 128x128 PiP. Each 64x64 model pixel is shown as 2x2.
    wire pip_on = video_active &&
                  (vga_x < 10'd128) &&
                  (vga_y < 10'd128);
    wire [5:0] pip_x = vga_x[6:1];
    wire [5:0] pip_y = vga_y[6:1];
    wire [11:0] pip_addr = {pip_y, pip_x};

    wire [11:0] gray_rd_addr =
        loader_owns_gray ? loader_addr : pip_addr;
    wire [7:0] gray_rd_data;

    gray64_mem u_gray64 (
        .wr_clk(cam_pclk),
        .wr_en(gray_wr_en),
        .wr_addr(gray_wr_addr),
        .wr_data(gray_wr_data),
        .rd_clk(pix_clk),
        .rd_addr(gray_rd_addr),
        .rd_data(gray_rd_data)
    );

    wire signed [15:0] normalized_pixel_q12;

    u8_to_q12_lut u_input_normalizer (
        .pixel_u8(gray_rd_data),
        .pixel_q12(normalized_pixel_q12)
    );

    wire accelerator_input_wr_en =
        (loader_state == LOAD_WRITE);
    wire accelerator_start =
        (loader_state == LOAD_START);

    wire accelerator_busy;
    wire accelerator_done;
    wire accelerator_detection_valid;
    wire [12:0] accelerator_confidence_q12;
    wire [2:0] accelerator_grid_x;
    wire [2:0] accelerator_grid_y;
    wire [6:0] detector_x1;
    wire [6:0] detector_y1;
    wire [6:0] detector_x2;
    wire [6:0] detector_y2;
    wire [6:0] detector_center_x;
    wire [6:0] detector_center_y;

    tiny_vehicle_full_accelerator_q12 u_accelerator (
        .clk(pix_clk),
        .reset_n(reset_n),
        .input_wr_en(accelerator_input_wr_en),
        .input_wr_addr(loader_addr),
        .input_wr_data(normalized_pixel_q12),
        .start(accelerator_start),
        .busy(accelerator_busy),
        .done(accelerator_done),
        .head_out_valid(),
        .head_out_addr(),
        .head_out_data(),
        .detection_valid(accelerator_detection_valid),
        .confidence_q12(accelerator_confidence_q12),
        .grid_x(accelerator_grid_x),
        .grid_y(accelerator_grid_y),
        .x1(detector_x1),
        .y1(detector_y1),
        .x2(detector_x2),
        .y2(detector_y2),
        .center_x(detector_center_x),
        .center_y(detector_center_y)
    );

    // ========================================================
    // Stable live-display detection
    // ========================================================
    // Raw CNN results are not displayed immediately. A box must appear in
    // approximately the same place for three consecutive inferences and
    // must have confidence >= 0.45. This rejects most one-frame false boxes.
    wire stable_detection_valid;
    wire [12:0] stable_confidence_q12;
    wire [6:0] stable_detector_x1;
    wire [6:0] stable_detector_y1;
    wire [6:0] stable_detector_x2;
    wire [6:0] stable_detector_y2;

    detection_stabilizer_q12 #(
        .MIN_CONFIDENCE_Q12(13'd1843),
        .REQUIRED_MATCHES(3),
        .MAX_MISSES(4),
        .MAX_CENTER_DELTA(7'd6),
        .MAX_SIZE_DELTA(7'd10)
    ) u_detection_stabilizer (
        .clk(pix_clk),
        .reset_n(reset_n),
        .sample_done(accelerator_done),
        .raw_valid(accelerator_detection_valid),
        .raw_confidence_q12(accelerator_confidence_q12),
        .raw_x1(detector_x1),
        .raw_y1(detector_y1),
        .raw_x2(detector_x2),
        .raw_y2(detector_y2),
        .stable_valid(stable_detection_valid),
        .stable_confidence_q12(stable_confidence_q12),
        .stable_x1(stable_detector_x1),
        .stable_y1(stable_detector_y1),
        .stable_x2(stable_detector_x2),
        .stable_y2(stable_detector_y2)
    );

    // gray64_mem has a one-clock synchronous read latency. LOAD_REQUEST
    // presents the address; LOAD_WRITE transfers the returned value.
    always @(posedge pix_clk or negedge reset_n) begin
        if (!reset_n) begin
            loader_state <= LOAD_IDLE;
            loader_addr  <= 12'd0;
        end else begin
            case (loader_state)
                LOAD_IDLE: begin
                    if (new_gray_frame && !accelerator_busy) begin
                        loader_addr  <= 12'd0;
                        loader_state <= LOAD_REQUEST;
                    end
                end

                LOAD_REQUEST: begin
                    loader_state <= LOAD_WRITE;
                end

                LOAD_WRITE: begin
                    if (loader_addr == 12'd4095) begin
                        loader_state <= LOAD_START;
                    end else begin
                        loader_addr  <= loader_addr + 1'b1;
                        loader_state <= LOAD_REQUEST;
                    end
                end

                LOAD_START: begin
                    loader_state <= LOAD_WAIT;
                end

                LOAD_WAIT: begin
                    if (accelerator_done)
                        loader_state <= LOAD_IDLE;
                end

                default: loader_state <= LOAD_IDLE;
            endcase
        end
    end

    // ========================================================
    // 7) Scale detector coordinates from 64x64 to 640x480
    // ========================================================
    wire [13:0] scaled_x1_raw = stable_detector_x1 * 14'd10;
    wire [13:0] scaled_x2_raw = stable_detector_x2 * 14'd10;
    wire [13:0] scaled_y1_raw = stable_detector_y1 * 14'd15;
    wire [13:0] scaled_y2_raw = stable_detector_y2 * 14'd15;

    wire [13:0] scaled_y1_half = scaled_y1_raw >> 1;
    wire [13:0] scaled_y2_half = scaled_y2_raw >> 1;

    wire [9:0] box_x1 =
        (scaled_x1_raw >= 14'd640) ? 10'd639 : scaled_x1_raw[9:0];
    wire [9:0] box_x2 =
        (scaled_x2_raw >= 14'd640) ? 10'd639 : scaled_x2_raw[9:0];
    wire [9:0] box_y1 =
        (scaled_y1_half >= 14'd480) ? 10'd479 : scaled_y1_half[9:0];
    wire [9:0] box_y2 =
        (scaled_y2_half >= 14'd480) ? 10'd479 : scaled_y2_half[9:0];

    // One-cycle alignment for synchronous display memories.
    reg video_active_d = 1'b0;
    reg pip_on_d = 1'b0;
    reg loader_owns_gray_d = 1'b0;
    reg [9:0] vga_x_d = 10'd0;
    reg [9:0] vga_y_d = 10'd0;

    always @(posedge pix_clk) begin
        video_active_d      <= video_active;
        pip_on_d            <= pip_on;
        loader_owns_gray_d  <= loader_owns_gray;
        vga_x_d             <= vga_x;
        vga_y_d             <= vga_y;
    end

    wire [4:0] base_r5 = fb_rd_data[15:11];
    wire [5:0] base_g6 = fb_rd_data[10:5];
    wire [4:0] base_b5 = fb_rd_data[4:0];

    wire [3:0] base_r = base_r5[4:1];
    wire [3:0] base_g = base_g6[5:2];
    wire [3:0] base_b = base_b5[4:1];
    wire [3:0] pip_gray = gray_rd_data[7:4];

    wire box_horizontal =
        (vga_x_d >= box_x1) && (vga_x_d <= box_x2) &&
        ((vga_y_d == box_y1) ||
         (vga_y_d == (box_y1 + 1'b1)) ||
         (vga_y_d == box_y2) ||
         ((box_y2 != 10'd0) && (vga_y_d == (box_y2 - 1'b1))));

    wire box_vertical =
        (vga_y_d >= box_y1) && (vga_y_d <= box_y2) &&
        ((vga_x_d == box_x1) ||
         (vga_x_d == (box_x1 + 1'b1)) ||
         (vga_x_d == box_x2) ||
         ((box_x2 != 10'd0) && (vga_x_d == (box_x2 - 1'b1))));

    wire box_pixel =
        video_active_d &&
        stable_detection_valid &&
        (box_horizontal || box_vertical);

    wire pip_pixel_valid =
        pip_on_d && !loader_owns_gray_d;

    // Draw VEHICLE above the stable box. When the box is close to the top
    // edge, draw the label just below its top edge.
    wire [9:0] label_origin_x =
        (box_x1 > 10'd557) ? 10'd557 : box_x1;

    wire [9:0] label_origin_y =
        (box_y1 >= 10'd16) ?
        (box_y1 - 10'd16) :
        ((box_y2 <= 10'd463) ? (box_y2 + 10'd2) : 10'd0);

    wire label_pixel;

    vehicle_label_5x7 u_vehicle_label (
        .enable(stable_detection_valid && video_active_d),
        .x(vga_x_d),
        .y(vga_y_d),
        .origin_x(label_origin_x),
        .origin_y(label_origin_y),
        .pixel(label_pixel)
    );

    wire detection_overlay_pixel = box_pixel || label_pixel;

    // Green bounding box and VEHICLE label have highest priority.
    assign vga_r = !video_active_d ? 4'h0 :
                   detection_overlay_pixel ? 4'h0 :
                   pip_pixel_valid ? pip_gray : base_r;

    assign vga_g = !video_active_d ? 4'h0 :
                   detection_overlay_pixel ? 4'hF :
                   pip_pixel_valid ? pip_gray : base_g;

    assign vga_b = !video_active_d ? 4'h0 :
                   detection_overlay_pixel ? 4'h0 :
                   pip_pixel_valid ? pip_gray : base_b;

    // ========================================================
    // 8) Status LEDs
    // ========================================================
    reg cam_vsync_d = 1'b0;
    reg [3:0] cam_frame_count = 4'd0;
    reg cam_frame_led = 1'b0;

    always @(posedge cam_pclk or negedge reset_n) begin
        if (!reset_n) begin
            cam_vsync_d     <= 1'b0;
            cam_frame_count <= 4'd0;
            cam_frame_led   <= 1'b0;
        end else begin
            cam_vsync_d <= cam_vsync;

            if (cam_vsync && !cam_vsync_d) begin
                if (cam_frame_count == 4'd14) begin
                    cam_frame_count <= 4'd0;
                    cam_frame_led   <= ~cam_frame_led;
                end else begin
                    cam_frame_count <= cam_frame_count + 1'b1;
                end
            end
        end
    end

    // LED2 becomes solid after the first completed inference. It no longer
    // flickers with every loading/inference cycle.
    reg accelerator_alive = 1'b0;

    always @(posedge pix_clk or negedge reset_n) begin
        if (!reset_n)
            accelerator_alive <= 1'b0;
        else if (accelerator_done)
            accelerator_alive <= 1'b1;
    end

    assign led[0] = cam_init_done;
    assign led[1] = cam_frame_led;
    assign led[2] = accelerator_alive;
    assign led[3] = stable_detection_valid;

endmodule
