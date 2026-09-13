`timescale 1ns / 1ps

// OV7670 UYVY stream:
// byte 0 = U, byte 1 = Y0, byte 2 = V, byte 3 = Y1.
//
// For a robust first hardware demonstration this module uses Y0 directly
// as grayscale. It stores one pixel from each 2x2 source area, creating
// a 320x240 RGB565 grayscale framebuffer. It also exports the full-frame
// Y0 coordinate stream for the 64x64 model input resize.

module cam_capture_gray_rgb565_320x240 (
    input  wire        pclk,
    input  wire        reset_n,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,

    output reg  [16:0] wr_addr,
    output reg         wr_en,
    output reg  [15:0] wr_data,

    output reg  [7:0]  y_full_pix,
    output reg         y_full_valid,
    output reg  [9:0]  x_full,
    output reg  [9:0]  y_full
);

    reg [9:0] x = 10'd0;
    reg [9:0] y = 10'd0;
    reg [1:0] phase = 2'd0;

    reg href_d = 1'b0;
    wire href_rise = href && !href_d;
    wire href_fall = !href && href_d;

    always @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 10'd0;
            y <= 10'd0;
            phase <= 2'd0;
            href_d <= 1'b0;

            wr_addr <= 17'd0;
            wr_en <= 1'b0;
            wr_data <= 16'd0;

            y_full_pix <= 8'd0;
            y_full_valid <= 1'b0;
            x_full <= 10'd0;
            y_full <= 10'd0;
        end else begin
            href_d <= href;
            wr_en <= 1'b0;
            y_full_valid <= 1'b0;

            if (vsync) begin
                x <= 10'd0;
                y <= 10'd0;
                phase <= 2'd0;
                wr_addr <= 17'd0;
            end else begin
                if (href_rise)
                    x <= 10'd0;

                if (href_fall)
                    y <= y + 1'b1;

                if (href) begin
                    case (phase)
                        2'd0: begin
                            // U byte
                            phase <= 2'd1;
                        end

                        2'd1: begin
                            // Y0 belongs to source coordinate (x,y).
                            y_full_pix <= d;
                            y_full_valid <= 1'b1;
                            x_full <= x;
                            y_full <= y;

                            // 2x2 downsample: keep even x and even y.
                            // x is always even for Y0 in this module.
                            if (!y[0]) begin
                                wr_addr <= (y[9:1] * 17'd320) + x[9:1];
                                wr_data <= {d[7:3], d[7:2], d[7:3]};
                                wr_en <= 1'b1;
                            end

                            phase <= 2'd2;
                        end

                        2'd2: begin
                            // V byte
                            phase <= 2'd3;
                        end

                        default: begin
                            // Y1 is skipped because Y0 already represents this pair.
                            x <= x + 10'd2;
                            phase <= 2'd0;
                        end
                    endcase
                end else begin
                    phase <= 2'd0;
                end
            end
        end
    end

endmodule
