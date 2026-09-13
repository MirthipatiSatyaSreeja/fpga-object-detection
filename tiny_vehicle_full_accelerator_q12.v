`timescale 1ns / 1ps

module tiny_vehicle_full_accelerator_q12 (
    input  wire clk,
    input  wire reset_n,

    // Load one normalized signed-Q12 64x64 image before asserting start.
    input  wire               input_wr_en,
    input  wire [11:0]        input_wr_addr,
    input  wire signed [15:0] input_wr_data,

    input  wire start,

    output reg busy,
    output reg done,

    output reg                head_out_valid,
    output reg [8:0]          head_out_addr,
    output reg signed [15:0]  head_out_data,

    output wire detection_valid,
    output wire [12:0] confidence_q12,
    output wire [2:0] grid_x,
    output wire [2:0] grid_y,
    output wire [6:0] x1,
    output wire [6:0] y1,
    output wire [6:0] x2,
    output wire [6:0] y2,
    output wire [6:0] center_x,
    output wire [6:0] center_y
);

    // ---------------------------------------------------------------------
    // Layer parameters.
    // Distributed ROM is intentional here because the datapath needs
    // asynchronous weight lookup. The two large feature maps use BRAM.
    // ---------------------------------------------------------------------
    (* rom_style = "distributed" *) reg signed [15:0] stem_weight [0:71];
    (* rom_style = "distributed" *) reg signed [31:0] stem_bias [0:7];

    (* rom_style = "distributed" *) reg signed [15:0] b1dw_weight [0:71];
    (* rom_style = "distributed" *) reg signed [31:0] b1dw_bias [0:7];

    (* rom_style = "distributed" *) reg signed [15:0] b1pw_weight [0:127];
    (* rom_style = "distributed" *) reg signed [31:0] b1pw_bias [0:15];

    (* rom_style = "distributed" *) reg signed [15:0] b2dw_weight [0:143];
    (* rom_style = "distributed" *) reg signed [31:0] b2dw_bias [0:15];

    (* rom_style = "distributed" *) reg signed [15:0] b2pw_weight [0:511];
    (* rom_style = "distributed" *) reg signed [31:0] b2pw_bias [0:31];

    (* rom_style = "distributed" *) reg signed [15:0] b3dw_weight [0:287];
    (* rom_style = "distributed" *) reg signed [31:0] b3dw_bias [0:31];

    (* rom_style = "distributed" *) reg signed [15:0] b3pw_weight [0:2047];
    (* rom_style = "distributed" *) reg signed [31:0] b3pw_bias [0:63];

    (* rom_style = "distributed" *) reg signed [15:0] head_weight [0:319];
    (* rom_style = "distributed" *) reg signed [31:0] head_bias [0:4];

    initial begin
        $readmemh("stem_conv_weight_q12.mem", stem_weight);
        $readmemh("stem_conv_bias_q12.mem", stem_bias);

        $readmemh("block1_depthwise_conv_weight_q12.mem", b1dw_weight);
        $readmemh("block1_depthwise_conv_bias_q12.mem", b1dw_bias);

        $readmemh("block1_pointwise_conv_weight_q12.mem", b1pw_weight);
        $readmemh("block1_pointwise_conv_bias_q12.mem", b1pw_bias);

        $readmemh("block2_depthwise_conv_weight_q12.mem", b2dw_weight);
        $readmemh("block2_depthwise_conv_bias_q12.mem", b2dw_bias);

        $readmemh("block2_pointwise_conv_weight_q12.mem", b2pw_weight);
        $readmemh("block2_pointwise_conv_bias_q12.mem", b2pw_bias);

        $readmemh("block3_depthwise_conv_weight_q12.mem", b3dw_weight);
        $readmemh("block3_depthwise_conv_bias_q12.mem", b3dw_bias);

        $readmemh("block3_pointwise_conv_weight_q12.mem", b3pw_weight);
        $readmemh("block3_pointwise_conv_bias_q12.mem", b3pw_bias);

        $readmemh("head_weight_q12.mem", head_weight);
        $readmemh("head_bias_q12.mem", head_bias);
    end

    // ---------------------------------------------------------------------
    // Controller and layer counters.
    // ---------------------------------------------------------------------
    localparam [3:0]
        S_IDLE          = 4'd0,
        S_INITIALIZE    = 4'd1,
        S_FETCH         = 4'd2,
        S_MAC           = 4'd3,
        S_WRITE         = 4'd4,
        S_NEXT_OUTPUT   = 4'd5,
        S_NEXT_LAYER    = 4'd6,
        S_START_DECODER = 4'd7,
        S_WAIT_DECODER  = 4'd8,
        S_FINISH        = 4'd9;

    reg [3:0] state;
    reg [2:0] layer_index;

    reg [6:0] output_channel;
    reg [5:0] output_y;
    reg [5:0] output_x;
    reg [6:0] input_channel;
    reg [1:0] kernel_y;
    reg [1:0] kernel_x;

    reg signed [47:0] accumulator;

    // Current-layer configuration.
    integer cfg_input_channels;
    integer cfg_output_channels;
    integer cfg_input_width;
    integer cfg_input_height;
    integer cfg_output_width;
    integer cfg_output_height;
    integer cfg_kernel_size;
    integer cfg_stride;
    integer cfg_padding;

    reg cfg_depthwise;
    reg cfg_relu;
    reg cfg_source_b;
    reg cfg_destination_b;

    integer source_channel_value;
    integer source_y_value;
    integer source_x_value;
    integer source_address_value;
    integer weight_address_value;
    integer destination_address_value;

    reg [12:0] source_bram_address;
    reg [12:0] destination_bram_address;

    reg source_inside_image;
    reg last_inner_operation;
    reg last_output_value;

    reg signed [31:0] current_bias_value;
    reg signed [15:0] selected_weight_value;

    // ---------------------------------------------------------------------
    // Layer configuration.
    // ---------------------------------------------------------------------
    always @(*) begin
        cfg_input_channels  = 1;
        cfg_output_channels = 8;
        cfg_input_width     = 64;
        cfg_input_height    = 64;
        cfg_output_width    = 32;
        cfg_output_height   = 32;
        cfg_kernel_size     = 3;
        cfg_stride          = 2;
        cfg_padding         = 1;
        cfg_depthwise       = 1'b0;
        cfg_relu            = 1'b1;
        cfg_source_b        = 1'b0;
        cfg_destination_b   = 1'b1;

        case (layer_index)
            3'd0: begin
                // Stem: 1x64x64 -> 8x32x32.
            end

            3'd1: begin
                cfg_input_channels  = 8;
                cfg_output_channels = 8;
                cfg_input_width     = 32;
                cfg_input_height    = 32;
                cfg_output_width    = 16;
                cfg_output_height   = 16;
                cfg_kernel_size     = 3;
                cfg_stride          = 2;
                cfg_padding         = 1;
                cfg_depthwise       = 1'b1;
                cfg_source_b        = 1'b1;
                cfg_destination_b   = 1'b0;
            end

            3'd2: begin
                cfg_input_channels  = 8;
                cfg_output_channels = 16;
                cfg_input_width     = 16;
                cfg_input_height    = 16;
                cfg_output_width    = 16;
                cfg_output_height   = 16;
                cfg_kernel_size     = 1;
                cfg_stride          = 1;
                cfg_padding         = 0;
                cfg_depthwise       = 1'b0;
                cfg_source_b        = 1'b0;
                cfg_destination_b   = 1'b1;
            end

            3'd3: begin
                cfg_input_channels  = 16;
                cfg_output_channels = 16;
                cfg_input_width     = 16;
                cfg_input_height    = 16;
                cfg_output_width    = 8;
                cfg_output_height   = 8;
                cfg_kernel_size     = 3;
                cfg_stride          = 2;
                cfg_padding         = 1;
                cfg_depthwise       = 1'b1;
                cfg_source_b        = 1'b1;
                cfg_destination_b   = 1'b0;
            end

            3'd4: begin
                cfg_input_channels  = 16;
                cfg_output_channels = 32;
                cfg_input_width     = 8;
                cfg_input_height    = 8;
                cfg_output_width    = 8;
                cfg_output_height   = 8;
                cfg_kernel_size     = 1;
                cfg_stride          = 1;
                cfg_padding         = 0;
                cfg_depthwise       = 1'b0;
                cfg_source_b        = 1'b0;
                cfg_destination_b   = 1'b1;
            end

            3'd5: begin
                cfg_input_channels  = 32;
                cfg_output_channels = 32;
                cfg_input_width     = 8;
                cfg_input_height    = 8;
                cfg_output_width    = 8;
                cfg_output_height   = 8;
                cfg_kernel_size     = 3;
                cfg_stride          = 1;
                cfg_padding         = 1;
                cfg_depthwise       = 1'b1;
                cfg_source_b        = 1'b1;
                cfg_destination_b   = 1'b0;
            end

            3'd6: begin
                cfg_input_channels  = 32;
                cfg_output_channels = 64;
                cfg_input_width     = 8;
                cfg_input_height    = 8;
                cfg_output_width    = 8;
                cfg_output_height   = 8;
                cfg_kernel_size     = 1;
                cfg_stride          = 1;
                cfg_padding         = 0;
                cfg_depthwise       = 1'b0;
                cfg_source_b        = 1'b0;
                cfg_destination_b   = 1'b1;
            end

            3'd7: begin
                cfg_input_channels  = 64;
                cfg_output_channels = 5;
                cfg_input_width     = 8;
                cfg_input_height    = 8;
                cfg_output_width    = 8;
                cfg_output_height   = 8;
                cfg_kernel_size     = 1;
                cfg_stride          = 1;
                cfg_padding         = 0;
                cfg_depthwise       = 1'b0;
                cfg_relu            = 1'b0;
                cfg_source_b        = 1'b1;
                cfg_destination_b   = 1'b0;
            end

            default: begin
            end
        endcase
    end

    // ---------------------------------------------------------------------
    // Address generation.
    // ---------------------------------------------------------------------
    always @(*) begin
        if (cfg_depthwise)
            source_channel_value = output_channel;
        else
            source_channel_value = input_channel;

        source_y_value =
            (output_y * cfg_stride) + kernel_y - cfg_padding;
        source_x_value =
            (output_x * cfg_stride) + kernel_x - cfg_padding;

        source_inside_image =
            (source_y_value >= 0) &&
            (source_y_value < cfg_input_height) &&
            (source_x_value >= 0) &&
            (source_x_value < cfg_input_width);

        source_address_value =
            (source_channel_value * cfg_input_width * cfg_input_height) +
            (source_y_value * cfg_input_width) +
            source_x_value;

        if (source_inside_image)
            source_bram_address = source_address_value;
        else
            source_bram_address = 13'd0;

        if (cfg_depthwise) begin
            weight_address_value =
                (output_channel * cfg_kernel_size * cfg_kernel_size) +
                (kernel_y * cfg_kernel_size) +
                kernel_x;
        end else begin
            weight_address_value =
                (output_channel *
                    cfg_input_channels *
                    cfg_kernel_size *
                    cfg_kernel_size) +
                (input_channel * cfg_kernel_size * cfg_kernel_size) +
                (kernel_y * cfg_kernel_size) +
                kernel_x;
        end

        destination_address_value =
            (output_channel * cfg_output_width * cfg_output_height) +
            (output_y * cfg_output_width) +
            output_x;

        destination_bram_address = destination_address_value;

        last_inner_operation =
            (kernel_x == cfg_kernel_size - 1) &&
            (kernel_y == cfg_kernel_size - 1) &&
            (cfg_depthwise ||
                (input_channel == cfg_input_channels - 1));

        last_output_value =
            (output_channel == cfg_output_channels - 1) &&
            (output_y == cfg_output_height - 1) &&
            (output_x == cfg_output_width - 1);
    end

    always @(*) begin
        current_bias_value = 32'sd0;

        case (layer_index)
            3'd0: current_bias_value = stem_bias[output_channel];
            3'd1: current_bias_value = b1dw_bias[output_channel];
            3'd2: current_bias_value = b1pw_bias[output_channel];
            3'd3: current_bias_value = b2dw_bias[output_channel];
            3'd4: current_bias_value = b2pw_bias[output_channel];
            3'd5: current_bias_value = b3dw_bias[output_channel];
            3'd6: current_bias_value = b3pw_bias[output_channel];
            3'd7: current_bias_value = head_bias[output_channel];
            default: current_bias_value = 32'sd0;
        endcase
    end

    always @(*) begin
        selected_weight_value = 16'sd0;

        case (layer_index)
            3'd0: selected_weight_value = stem_weight[weight_address_value];
            3'd1: selected_weight_value = b1dw_weight[weight_address_value];
            3'd2: selected_weight_value = b1pw_weight[weight_address_value];
            3'd3: selected_weight_value = b2dw_weight[weight_address_value];
            3'd4: selected_weight_value = b2pw_weight[weight_address_value];
            3'd5: selected_weight_value = b3dw_weight[weight_address_value];
            3'd6: selected_weight_value = b3pw_weight[weight_address_value];
            3'd7: selected_weight_value = head_weight[weight_address_value];
            default: selected_weight_value = 16'sd0;
        endcase
    end

    // ---------------------------------------------------------------------
    // Quantization.
    // ---------------------------------------------------------------------
    function signed [15:0] relu_round_q12;
        input signed [47:0] value_q24;
        reg signed [47:0] rounded_value;
        reg signed [47:0] shifted_value;
        begin
            if (value_q24 <= 0) begin
                relu_round_q12 = 16'sd0;
            end else begin
                rounded_value = value_q24 + 48'sd2048;
                shifted_value = rounded_value >>> 12;

                if (shifted_value > 48'sd32767)
                    relu_round_q12 = 16'sh7fff;
                else
                    relu_round_q12 = shifted_value[15:0];
            end
        end
    endfunction

    function signed [15:0] signed_round_q12;
        input signed [47:0] value_q24;
        reg signed [47:0] rounded_value;
        reg signed [47:0] shifted_value;
        begin
            if (value_q24 >= 0)
                rounded_value = value_q24 + 48'sd2048;
            else
                rounded_value = value_q24 - 48'sd2048;

            shifted_value = rounded_value >>> 12;

            if (shifted_value > 48'sd32767)
                signed_round_q12 = 16'sh7fff;
            else if (shifted_value < -48'sd32768)
                signed_round_q12 = 16'sh8000;
            else
                signed_round_q12 = shifted_value[15:0];
        end
    endfunction

    reg signed [15:0] quantized_output_value;

    always @(*) begin
        if (cfg_relu)
            quantized_output_value = relu_round_q12(accumulator);
        else
            quantized_output_value = signed_round_q12(accumulator);
    end

    // ---------------------------------------------------------------------
    // BRAM ping-pong buffers.
    // A single write mux prevents the unsupported multiple-writer pattern.
    // ---------------------------------------------------------------------
    wire input_loader_write =
        input_wr_en && !busy;

    wire internal_write =
        (state == S_WRITE);

    wire activation_a_wr_en =
        input_loader_write ||
        (internal_write && !cfg_destination_b);

    wire activation_b_wr_en =
        internal_write && cfg_destination_b;

    wire [12:0] activation_a_wr_addr =
        input_loader_write
            ? {1'b0, input_wr_addr}
            : destination_bram_address;

    wire signed [15:0] activation_a_wr_data =
        input_loader_write
            ? input_wr_data
            : quantized_output_value;

    wire [12:0] activation_b_wr_addr =
        destination_bram_address;

    wire signed [15:0] activation_b_wr_data =
        quantized_output_value;

    wire signed [15:0] activation_a_rd_data;
    wire signed [15:0] activation_b_rd_data;

    feature_map_bram_q12 activation_a_bram (
        .clk     (clk),
        .wr_en   (activation_a_wr_en),
        .wr_addr (activation_a_wr_addr),
        .wr_data (activation_a_wr_data),
        .rd_addr (source_bram_address),
        .rd_data (activation_a_rd_data)
    );

    feature_map_bram_q12 activation_b_bram (
        .clk     (clk),
        .wr_en   (activation_b_wr_en),
        .wr_addr (activation_b_wr_addr),
        .wr_data (activation_b_wr_data),
        .rd_addr (source_bram_address),
        .rd_data (activation_b_rd_data)
    );

    wire signed [15:0] source_activation_value =
        source_inside_image
            ? (cfg_source_b
                ? activation_b_rd_data
                : activation_a_rd_data)
            : 16'sd0;

    // ---------------------------------------------------------------------
    // Decoder.
    // ---------------------------------------------------------------------
    reg decoder_wr_en;
    reg [8:0] decoder_wr_addr;
    reg signed [15:0] decoder_wr_data;
    reg decoder_start;

    wire decoder_busy;
    wire decoder_done;

    vehicle_decoder_q12 decoder (
        .clk             (clk),
        .reset_n         (reset_n),
        .head_wr_en      (decoder_wr_en),
        .head_wr_addr    (decoder_wr_addr),
        .head_wr_data    (decoder_wr_data),
        .start           (decoder_start),
        .busy            (decoder_busy),
        .done            (decoder_done),
        .detection_valid (detection_valid),
        .confidence_q12  (confidence_q12),
        .grid_x          (grid_x),
        .grid_y          (grid_y),
        .x1              (x1),
        .y1              (y1),
        .x2              (x2),
        .y2              (y2),
        .center_x        (center_x),
        .center_y        (center_y)
    );

    // ---------------------------------------------------------------------
    // Main sequential controller.
    //
    // S_FETCH is the one-cycle wait required by synchronous BRAM reads.
    // At the following S_MAC edge, rd_data contains the requested value.
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;

            head_out_valid <= 1'b0;
            head_out_addr  <= 9'd0;
            head_out_data  <= 16'sd0;

            decoder_wr_en   <= 1'b0;
            decoder_wr_addr <= 9'd0;
            decoder_wr_data <= 16'sd0;
            decoder_start   <= 1'b0;

            layer_index    <= 3'd0;
            output_channel <= 7'd0;
            output_y       <= 6'd0;
            output_x       <= 6'd0;
            input_channel  <= 7'd0;
            kernel_y       <= 2'd0;
            kernel_x       <= 2'd0;
            accumulator    <= 48'sd0;
        end else begin
            done           <= 1'b0;
            head_out_valid <= 1'b0;
            decoder_wr_en  <= 1'b0;
            decoder_start  <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        busy           <= 1'b1;
                        layer_index    <= 3'd0;
                        output_channel <= 7'd0;
                        output_y       <= 6'd0;
                        output_x       <= 6'd0;
                        input_channel  <= 7'd0;
                        kernel_y       <= 2'd0;
                        kernel_x       <= 2'd0;
                        state          <= S_INITIALIZE;
                    end
                end

                S_INITIALIZE: begin
                    accumulator   <= $signed(current_bias_value) <<< 12;
                    input_channel <= 7'd0;
                    kernel_y      <= 2'd0;
                    kernel_x      <= 2'd0;
                    state         <= S_FETCH;
                end

                S_FETCH: begin
                    // The BRAM samples source_bram_address on this edge.
                    state <= S_MAC;
                end

                S_MAC: begin
                    accumulator <=
                        accumulator +
                        ($signed(source_activation_value) *
                         $signed(selected_weight_value));

                    if (last_inner_operation) begin
                        state <= S_WRITE;
                    end else begin
                        if (kernel_x == cfg_kernel_size - 1) begin
                            kernel_x <= 2'd0;

                            if (kernel_y == cfg_kernel_size - 1) begin
                                kernel_y <= 2'd0;

                                if (!cfg_depthwise)
                                    input_channel <= input_channel + 1'b1;
                            end else begin
                                kernel_y <= kernel_y + 1'b1;
                            end
                        end else begin
                            kernel_x <= kernel_x + 1'b1;
                        end

                        state <= S_FETCH;
                    end
                end

                S_WRITE: begin
                    // BRAM writes are performed by feature_map_bram_q12
                    // through activation_a_wr_en/activation_b_wr_en.

                    if (layer_index == 3'd7) begin
                        head_out_valid  <= 1'b1;
                        head_out_addr   <= destination_bram_address[8:0];
                        head_out_data   <= quantized_output_value;

                        decoder_wr_en   <= 1'b1;
                        decoder_wr_addr <= destination_bram_address[8:0];
                        decoder_wr_data <= quantized_output_value;
                    end

                    if (last_output_value) begin
                        if (layer_index == 3'd7)
                            state <= S_START_DECODER;
                        else
                            state <= S_NEXT_LAYER;
                    end else begin
                        state <= S_NEXT_OUTPUT;
                    end
                end

                S_NEXT_OUTPUT: begin
                    if (output_x == cfg_output_width - 1) begin
                        output_x <= 6'd0;

                        if (output_y == cfg_output_height - 1) begin
                            output_y       <= 6'd0;
                            output_channel <= output_channel + 1'b1;
                        end else begin
                            output_y <= output_y + 1'b1;
                        end
                    end else begin
                        output_x <= output_x + 1'b1;
                    end

                    state <= S_INITIALIZE;
                end

                S_NEXT_LAYER: begin
                    layer_index    <= layer_index + 1'b1;
                    output_channel <= 7'd0;
                    output_y       <= 6'd0;
                    output_x       <= 6'd0;
                    input_channel  <= 7'd0;
                    kernel_y       <= 2'd0;
                    kernel_x       <= 2'd0;
                    state          <= S_INITIALIZE;
                end

                S_START_DECODER: begin
                    decoder_start <= 1'b1;
                    state <= S_WAIT_DECODER;
                end

                S_WAIT_DECODER: begin
                    if (decoder_done)
                        state <= S_FINISH;
                end

                S_FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
