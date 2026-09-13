`timescale 1ns / 1ps

module resize_whole_640x480_to_64x64 (
    input  wire        pclk,
    input  wire        reset_n,
    input  wire        vsync,
    input  wire        pix_valid,
    input  wire [9:0]  x_full,
    input  wire [9:0]  y_full,
    input  wire [7:0]  y_in,

    output reg         wr_en,
    output reg  [11:0] wr_addr,
    output reg  [7:0]  wr_data,
    output reg         frame_toggle
);

    reg [5:0] ox = 6'd0;
    reg [5:0] oy = 6'd0;
    reg [9:0] x_tgt = 10'd0;
    reg [9:0] y_tgt = 10'd0;

    function [9:0] y_target;
        input [5:0] y_index;
        reg [15:0] product;
        begin
            product = y_index * 16'd480;
            y_target = product >> 6;
        end
    endfunction

    always @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            ox <= 6'd0;
            oy <= 6'd0;
            x_tgt <= 10'd0;
            y_tgt <= 10'd0;
            wr_en <= 1'b0;
            wr_addr <= 12'd0;
            wr_data <= 8'd0;
            frame_toggle <= 1'b0;
        end else begin
            wr_en <= 1'b0;

            if (vsync) begin
                ox <= 6'd0;
                oy <= 6'd0;
                x_tgt <= 10'd0;
                y_tgt <= 10'd0;
            end else if (pix_valid) begin
                if ((x_full == x_tgt) && (y_full == y_tgt)) begin
                    wr_addr <= {oy, ox};
                    wr_data <= y_in;
                    wr_en <= 1'b1;

                    if (ox == 6'd63) begin
                        ox <= 6'd0;
                        x_tgt <= 10'd0;

                        if (oy == 6'd63) begin
                            oy <= 6'd0;
                            y_tgt <= 10'd0;
                            frame_toggle <= ~frame_toggle;
                        end else begin
                            oy <= oy + 1'b1;
                            y_tgt <= y_target(oy + 1'b1);
                        end
                    end else begin
                        ox <= ox + 1'b1;
                        x_tgt <= (ox + 1'b1) * 10'd10;
                    end
                end
            end
        end
    end

endmodule
