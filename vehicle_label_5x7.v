`timescale 1ns / 1ps

// Draws the word VEHICLE using a 5x7 font enlarged 2x.
// Resulting text size is 82x14 pixels.
module vehicle_label_5x7 (
    input  wire       enable,
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [9:0] origin_x,
    input  wire [9:0] origin_y,
    output reg        pixel
);

    integer local_x;
    integer local_y;
    integer character_index;
    integer character_x;
    integer font_column;
    integer font_row;

    reg [4:0] row_pattern;

    function [4:0] glyph_row;
        input [2:0] character;
        input [2:0] row;
        begin
            glyph_row = 5'b00000;

            case (character)
                3'd0: begin // V
                    case (row)
                        3'd0, 3'd1, 3'd2, 3'd3, 3'd4:
                            glyph_row = 5'b10001;
                        3'd5: glyph_row = 5'b01010;
                        3'd6: glyph_row = 5'b00100;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                3'd1: begin // E
                    case (row)
                        3'd0, 3'd6: glyph_row = 5'b11111;
                        3'd1, 3'd2, 3'd4, 3'd5:
                            glyph_row = 5'b10000;
                        3'd3: glyph_row = 5'b11110;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                3'd2: begin // H
                    case (row)
                        3'd3: glyph_row = 5'b11111;
                        3'd0, 3'd1, 3'd2, 3'd4, 3'd5, 3'd6:
                            glyph_row = 5'b10001;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                3'd3: begin // I
                    case (row)
                        3'd0, 3'd6: glyph_row = 5'b11111;
                        3'd1, 3'd2, 3'd3, 3'd4, 3'd5:
                            glyph_row = 5'b00100;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                3'd4: begin // C
                    case (row)
                        3'd0, 3'd6: glyph_row = 5'b01111;
                        3'd1, 3'd2, 3'd3, 3'd4, 3'd5:
                            glyph_row = 5'b10000;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                3'd5: begin // L
                    case (row)
                        3'd0, 3'd1, 3'd2, 3'd3, 3'd4, 3'd5:
                            glyph_row = 5'b10000;
                        3'd6: glyph_row = 5'b11111;
                        default: glyph_row = 5'b00000;
                    endcase
                end

                default: begin // second E
                    case (row)
                        3'd0, 3'd6: glyph_row = 5'b11111;
                        3'd1, 3'd2, 3'd4, 3'd5:
                            glyph_row = 5'b10000;
                        3'd3: glyph_row = 5'b11110;
                        default: glyph_row = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    always @(*) begin
        pixel = 1'b0;
        local_x = 0;
        local_y = 0;
        character_index = 0;
        character_x = 0;
        font_column = 0;
        font_row = 0;
        row_pattern = 5'b00000;

        if (enable &&
            (x >= origin_x) && (x < origin_x + 10'd82) &&
            (y >= origin_y) && (y < origin_y + 10'd14)) begin

            local_x = x - origin_x;
            local_y = y - origin_y;

            character_index = local_x / 12;
            character_x = local_x - (character_index * 12);

            // Each font pixel is 2x2; two blank pixels separate letters.
            if ((character_index < 7) && (character_x < 10)) begin
                font_column = character_x >> 1;
                font_row = local_y >> 1;

                row_pattern =
                    glyph_row(character_index[2:0], font_row[2:0]);

                pixel = row_pattern[4 - font_column];
            end
        end
    end

endmodule
