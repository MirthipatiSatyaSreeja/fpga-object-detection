`timescale 1ns / 1ps

// Rejects one-frame false positives and smooths accepted bounding boxes.
// Coordinates are in the detector's 64x64 coordinate system.
module detection_stabilizer_q12 #(
    // 1843 / 4096 = approximately 0.45.
    parameter [12:0] MIN_CONFIDENCE_Q12 = 13'd1843,
    parameter integer REQUIRED_MATCHES = 3,
    parameter integer MAX_MISSES = 4,
    parameter [6:0] MAX_CENTER_DELTA = 7'd6,
    parameter [6:0] MAX_SIZE_DELTA = 7'd10
)(
    input  wire clk,
    input  wire reset_n,
    input  wire sample_done,

    input  wire        raw_valid,
    input  wire [12:0] raw_confidence_q12,
    input  wire [6:0]  raw_x1,
    input  wire [6:0]  raw_y1,
    input  wire [6:0]  raw_x2,
    input  wire [6:0]  raw_y2,

    output reg         stable_valid,
    output reg  [12:0] stable_confidence_q12,
    output reg  [6:0]  stable_x1,
    output reg  [6:0]  stable_y1,
    output reg  [6:0]  stable_x2,
    output reg  [6:0]  stable_y2
);

    reg candidate_valid;
    reg [6:0] candidate_x1;
    reg [6:0] candidate_y1;
    reg [6:0] candidate_x2;
    reg [6:0] candidate_y2;

    reg [2:0] match_count;
    reg [2:0] miss_count;

    wire [7:0] raw_x_sum = raw_x1 + raw_x2;
    wire [7:0] raw_y_sum = raw_y1 + raw_y2;
    wire [6:0] raw_center_x = raw_x_sum[7:1];
    wire [6:0] raw_center_y = raw_y_sum[7:1];
    wire [6:0] raw_width =
        (raw_x2 >= raw_x1) ? (raw_x2 - raw_x1) : 7'd0;
    wire [6:0] raw_height =
        (raw_y2 >= raw_y1) ? (raw_y2 - raw_y1) : 7'd0;

    wire [7:0] candidate_x_sum = candidate_x1 + candidate_x2;
    wire [7:0] candidate_y_sum = candidate_y1 + candidate_y2;
    wire [6:0] candidate_center_x = candidate_x_sum[7:1];
    wire [6:0] candidate_center_y = candidate_y_sum[7:1];
    wire [6:0] candidate_width =
        (candidate_x2 >= candidate_x1) ?
        (candidate_x2 - candidate_x1) : 7'd0;
    wire [6:0] candidate_height =
        (candidate_y2 >= candidate_y1) ?
        (candidate_y2 - candidate_y1) : 7'd0;

    function [6:0] abs_diff7;
        input [6:0] a;
        input [6:0] b;
        begin
            abs_diff7 = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    wire candidate_matches =
        candidate_valid &&
        (abs_diff7(raw_center_x, candidate_center_x) <= MAX_CENTER_DELTA) &&
        (abs_diff7(raw_center_y, candidate_center_y) <= MAX_CENTER_DELTA) &&
        (abs_diff7(raw_width, candidate_width) <= MAX_SIZE_DELTA) &&
        (abs_diff7(raw_height, candidate_height) <= MAX_SIZE_DELTA);

    wire raw_is_usable =
        raw_valid &&
        (raw_confidence_q12 >= MIN_CONFIDENCE_Q12) &&
        (raw_x2 > raw_x1) &&
        (raw_y2 > raw_y1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            candidate_valid       <= 1'b0;
            candidate_x1          <= 7'd0;
            candidate_y1          <= 7'd0;
            candidate_x2          <= 7'd0;
            candidate_y2          <= 7'd0;
            match_count           <= 3'd0;
            miss_count            <= 3'd0;

            stable_valid          <= 1'b0;
            stable_confidence_q12 <= 13'd0;
            stable_x1             <= 7'd0;
            stable_y1             <= 7'd0;
            stable_x2             <= 7'd0;
            stable_y2             <= 7'd0;
        end else if (sample_done) begin
            if (raw_is_usable) begin
                miss_count <= 3'd0;

                if (candidate_matches) begin
                    candidate_x1 <= raw_x1;
                    candidate_y1 <= raw_y1;
                    candidate_x2 <= raw_x2;
                    candidate_y2 <= raw_y2;

                    if (match_count < REQUIRED_MATCHES)
                        match_count <= match_count + 1'b1;

                    if (match_count >= REQUIRED_MATCHES - 1) begin
                        stable_valid <= 1'b1;

                        if (stable_valid) begin
                            // 3/4 old value + 1/4 new value.
                            stable_x1 <=
                                ((stable_x1 * 3) + raw_x1 + 2) >> 2;
                            stable_y1 <=
                                ((stable_y1 * 3) + raw_y1 + 2) >> 2;
                            stable_x2 <=
                                ((stable_x2 * 3) + raw_x2 + 2) >> 2;
                            stable_y2 <=
                                ((stable_y2 * 3) + raw_y2 + 2) >> 2;
                            stable_confidence_q12 <=
                                ((stable_confidence_q12 * 3) +
                                 raw_confidence_q12 + 2) >> 2;
                        end else begin
                            stable_x1 <= raw_x1;
                            stable_y1 <= raw_y1;
                            stable_x2 <= raw_x2;
                            stable_y2 <= raw_y2;
                            stable_confidence_q12 <= raw_confidence_q12;
                        end
                    end
                end else begin
                    candidate_valid <= 1'b1;
                    candidate_x1 <= raw_x1;
                    candidate_y1 <= raw_y1;
                    candidate_x2 <= raw_x2;
                    candidate_y2 <= raw_y2;
                    match_count <= 3'd1;
                end
            end else begin
                candidate_valid <= 1'b0;
                match_count <= 3'd0;

                if (stable_valid) begin
                    if (miss_count >= MAX_MISSES - 1) begin
                        stable_valid <= 1'b0;
                        miss_count <= 3'd0;
                    end else begin
                        miss_count <= miss_count + 1'b1;
                    end
                end else begin
                    miss_count <= 3'd0;
                end
            end
        end
    end

endmodule
