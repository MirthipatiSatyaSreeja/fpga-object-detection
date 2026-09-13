`timescale 1ns / 1ps

module ov7670_init (
    input  wire clk,
    input  wire reset_n,

    output reg  scl_drive_low,
    output reg  sda_drive_low,
    output reg  init_done
);

    localparam [7:0] DEV_ADDR = 8'h42;

    // 100 MHz / 2500 = one state-machine tick every 25 us.
    localparam integer DIVIDER = 2500;

    reg [15:0] tick_cnt = 16'd0;
    wire tick = (tick_cnt == 0);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            tick_cnt <= 16'd0;
        else if (tick_cnt == DIVIDER - 1)
            tick_cnt <= 16'd0;
        else
            tick_cnt <= tick_cnt + 1'b1;
    end

    // UYVY is selected intentionally:
    // TSLB[3]=1 and COM13[1]=0 -> U Y V Y.
    localparam integer NUM_REGS = 10;
    reg [15:0] cfg [0:NUM_REGS-1];

    initial begin
        cfg[0] = {8'h12, 8'h80}; // COM7: software reset
        cfg[1] = {8'h12, 8'h00}; // COM7: VGA, YUV
        cfg[2] = {8'h8C, 8'h00}; // RGB444 disable
        cfg[3] = {8'h3A, 8'h08}; // TSLB: UYVY byte order
        cfg[4] = {8'h40, 8'hC0}; // COM15: full output range
        cfg[5] = {8'h3D, 8'h40}; // COM13: UV auto adjust, no UV swap
        cfg[6] = {8'h11, 8'h01}; // CLKRC
        cfg[7] = {8'h6B, 8'h0A}; // DBLV/PLL setting
        cfg[8] = {8'h13, 8'hE7}; // COM8: AGC/AEC/AWB
        cfg[9] = {8'h0C, 8'h00}; // COM3: default
    end

    localparam [3:0]
        S_IDLE      = 4'd0,
        S_START1    = 4'd1,
        S_START2    = 4'd2,
        S_SEND_DEV  = 4'd3,
        S_DEV_ACK   = 4'd4,
        S_SEND_REG  = 4'd5,
        S_REG_ACK   = 4'd6,
        S_SEND_DATA = 4'd7,
        S_DATA_ACK  = 4'd8,
        S_STOP1     = 4'd9,
        S_STOP2     = 4'd10,
        S_NEXT      = 4'd11,
        S_DONE      = 4'd12,
        S_WAIT      = 4'd13;

    reg [3:0] state = S_IDLE;
    reg [7:0] byte_to_send = 8'd0;
    reg [3:0] bit_cnt = 4'd0;
    reg [1:0] phase = 2'd0;
    reg [1:0] ack_phase = 2'd0;
    reg [7:0] reg_index = 8'd0;
    reg [9:0] wait_count = 10'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_IDLE;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            init_done     <= 1'b0;
            byte_to_send  <= 8'd0;
            bit_cnt       <= 4'd0;
            phase         <= 2'd0;
            ack_phase     <= 2'd0;
            reg_index     <= 8'd0;
            wait_count    <= 10'd0;
        end else if (tick && !init_done) begin
            case (state)
                S_IDLE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    reg_index     <= 8'd0;
                    state         <= S_START1;
                end

                S_START1: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state         <= S_START2;
                end

                S_START2: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b1;
                    byte_to_send  <= DEV_ADDR;
                    bit_cnt       <= 4'd7;
                    phase         <= 2'd0;
                    state         <= S_SEND_DEV;
                end

                S_SEND_DEV: begin
                    case (phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= byte_to_send[bit_cnt] ? 1'b0 : 1'b1;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            if (bit_cnt == 0) begin
                                sda_drive_low <= 1'b0;
                                ack_phase <= 2'd0;
                                state <= S_DEV_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                                phase <= 2'd0;
                            end
                        end
                    endcase
                end

                S_DEV_ACK: begin
                    case (ack_phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b0;
                            ack_phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            ack_phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            byte_to_send <= cfg[reg_index][15:8];
                            bit_cnt <= 4'd7;
                            phase <= 2'd0;
                            state <= S_SEND_REG;
                        end
                    endcase
                end

                S_SEND_REG: begin
                    case (phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= byte_to_send[bit_cnt] ? 1'b0 : 1'b1;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            if (bit_cnt == 0) begin
                                sda_drive_low <= 1'b0;
                                ack_phase <= 2'd0;
                                state <= S_REG_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                                phase <= 2'd0;
                            end
                        end
                    endcase
                end

                S_REG_ACK: begin
                    case (ack_phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b0;
                            ack_phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            ack_phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            byte_to_send <= cfg[reg_index][7:0];
                            bit_cnt <= 4'd7;
                            phase <= 2'd0;
                            state <= S_SEND_DATA;
                        end
                    endcase
                end

                S_SEND_DATA: begin
                    case (phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= byte_to_send[bit_cnt] ? 1'b0 : 1'b1;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            if (bit_cnt == 0) begin
                                sda_drive_low <= 1'b0;
                                ack_phase <= 2'd0;
                                state <= S_DATA_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                                phase <= 2'd0;
                            end
                        end
                    endcase
                end

                S_DATA_ACK: begin
                    case (ack_phase)
                        2'd0: begin
                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b0;
                            ack_phase <= 2'd1;
                        end
                        2'd1: begin
                            scl_drive_low <= 1'b0;
                            ack_phase <= 2'd2;
                        end
                        default: begin
                            scl_drive_low <= 1'b1;
                            state <= S_STOP1;
                        end
                    endcase
                end

                S_STOP1: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b1;
                    state <= S_STOP2;
                end

                S_STOP2: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (reg_index == NUM_REGS - 1) begin
                        state <= S_DONE;
                    end else if (reg_index == 0) begin
                        // OV7670 requires time after COM7 software reset.
                        wait_count <= 10'd400; // about 10 ms
                        state <= S_WAIT;
                    end else begin
                        reg_index <= reg_index + 1'b1;
                        state <= S_START1;
                    end
                end

                S_WAIT: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    if (wait_count == 0) begin
                        reg_index <= reg_index + 1'b1;
                        state <= S_START1;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end

                S_DONE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    init_done <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
