`timescale 1ns / 1ps

// Exact hardware equivalent of the training normalization:
// q12 = round((uint8_pixel / 255.0) * 4096).
module u8_to_q12_lut (
    input  wire [7:0] pixel_u8,
    output wire signed [15:0] pixel_q12
);
    (* rom_style = "distributed" *)
    reg signed [15:0] lut [0:255];

    initial begin
        $readmemh("u8_to_q12_lut.mem", lut);
    end

    assign pixel_q12 = lut[pixel_u8];
endmodule
