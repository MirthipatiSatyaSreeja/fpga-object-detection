`timescale 1ns / 1ps

module vga_640x480 (
    input  wire       clk,
    input  wire       reset_n,
    output wire       hs,
    output wire       vs,
    output wire       active,
    output wire [9:0] x,
    output wire [9:0] y
);

    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 16;
    localparam integer H_SYNC   = 96;
    localparam integer H_BACK   = 48;
    localparam integer H_TOTAL  = 800;

    localparam integer V_ACTIVE = 480;
    localparam integer V_FRONT  = 10;
    localparam integer V_SYNC   = 2;
    localparam integer V_BACK   = 33;
    localparam integer V_TOTAL  = 525;

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (h_cnt == H_TOTAL - 1) begin
            h_cnt <= 10'd0;
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    assign active = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    assign hs = ~(
        (h_cnt >= H_ACTIVE + H_FRONT) &&
        (h_cnt <  H_ACTIVE + H_FRONT + H_SYNC)
    );

    assign vs = ~(
        (v_cnt >= V_ACTIVE + V_FRONT) &&
        (v_cnt <  V_ACTIVE + V_FRONT + V_SYNC)
    );

    assign x = h_cnt;
    assign y = v_cnt;

endmodule
