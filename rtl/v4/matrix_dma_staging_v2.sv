`timescale 1ns/1ps

module matrix_dma_staging_v2 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire        matrix_sel,
    output wire        cmd_ready,
    output wire        busy,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    input  wire        dma_status_valid,
    input  wire [7:0]  dma_status_tag,
    input  wire [3:0]  dma_status_error,

    output reg         operand_done,
    output reg         operand_error,
    output reg         pair_valid,

    input  wire [3:0]  rd_index,
    output wire [7:0]  a_rd_data,
    output wire [7:0]  b_rd_data
);

    localparam [1:0] IDLE = 2'd0, ACTIVE = 2'd1, DRAIN = 2'd2;

    reg [1:0] state;
    reg selected_matrix;
    reg [7:0] expected_tag;

    reg [2:0] beat_count;
    reg stream_complete;
    reg frame_error;

    reg status_seen;
    reg status_failed;

    reg a_valid;
    reg b_valid;

    reg [7:0] a_mem [0:15];
    reg [7:0] b_mem [0:15];

    wire stream_fire =
        s_axis_tvalid && s_axis_tready;

    wire status_fire =
        dma_status_valid && (state == ACTIVE);

    wire status_bad_now =
        (dma_status_tag != expected_tag) ||
        (dma_status_error != 4'd0);

    wire status_available =
        status_seen || status_fire;

    wire status_bad =
        status_failed ||
        (status_fire && status_bad_now);

    wire frame_done_now =
        stream_fire && (beat_count == 3);

    wire frame_bad_now =
        stream_fire &&
        ((s_axis_tkeep != 4'hF) ||
         (s_axis_tlast != (beat_count == 3)));

    wire data_complete =
        stream_complete || frame_done_now;

    wire data_bad =
        frame_error || frame_bad_now;

    assign cmd_ready = (state == IDLE);
    assign busy = (state != IDLE);

    assign s_axis_tready =
        ((state == ACTIVE) && !stream_complete &&
         (beat_count < 4) && !status_failed) ||
        (state == DRAIN);

    assign a_rd_data = a_mem[rd_index];
    assign b_rd_data = b_mem[rd_index];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            selected_matrix <= 0;
            expected_tag <= 0;

            beat_count <= 0;
            stream_complete <= 0;
            frame_error <= 0;

            status_seen <= 0;
            status_failed <= 0;

            a_valid <= 0;
            b_valid <= 0;
            pair_valid <= 0;

            operand_done <= 0;
            operand_error <= 0;

            for (i = 0; i < 16; i = i + 1) begin
                a_mem[i] <= 0;
                b_mem[i] <= 0;
            end
        end
        else begin
            operand_done <= 0;
            operand_error <= 0;

            case (state)
                IDLE: begin
                    if (start) begin
                        if (matrix_sel && !a_valid) begin
                            operand_error <= 1;
                        end
                        else begin
                            selected_matrix <= matrix_sel;

                            expected_tag <=
                                matrix_sel ? 8'hB1 : 8'hA1;

                            beat_count <= 0;
                            stream_complete <= 0;
                            frame_error <= 0;

                            status_seen <= 0;
                            status_failed <= 0;

                            if (!matrix_sel) begin
                                a_valid <= 0;
                                b_valid <= 0;
                                pair_valid <= 0;
                            end

                            state <= ACTIVE;
                        end
                    end
                end

                ACTIVE: begin
                    if (status_fire) begin
                        status_seen <= 1;

                        if (status_bad_now)
                            status_failed <= 1;
                    end

                    if (stream_fire) begin
                        if (!selected_matrix) begin
                            a_mem[beat_count*4+0]
                                <= s_axis_tdata[7:0];
                            a_mem[beat_count*4+1]
                                <= s_axis_tdata[15:8];
                            a_mem[beat_count*4+2]
                                <= s_axis_tdata[23:16];
                            a_mem[beat_count*4+3]
                                <= s_axis_tdata[31:24];
                        end
                        else begin
                            b_mem[beat_count*4+0]
                                <= s_axis_tdata[7:0];
                            b_mem[beat_count*4+1]
                                <= s_axis_tdata[15:8];
                            b_mem[beat_count*4+2]
                                <= s_axis_tdata[23:16];
                            b_mem[beat_count*4+3]
                                <= s_axis_tdata[31:24];
                        end

                        if (frame_bad_now)
                            frame_error <= 1;

                        beat_count <= beat_count + 1'b1;

                        if (beat_count == 3)
                            stream_complete <= 1;
                    end

                    if (status_available) begin
                        if (status_bad) begin
                            pair_valid <= 0;

                            if (!selected_matrix)
                                a_valid <= 0;
                            else
                                b_valid <= 0;

                            // Do not release this job until all output
                            // stream beats have been consumed. DMA status
                            // can precede the final AXI-Stream handshake.
                            if (stream_complete ||
                                (stream_fire && s_axis_tlast)) begin
                                operand_error <= 1;
                                state <= IDLE;
                            end
                            else begin
                                state <= DRAIN;
                            end
                        end
                        else if (data_complete) begin
                            if (data_bad) begin
                                operand_error <= 1;
                                pair_valid <= 0;

                                if (!selected_matrix)
                                    a_valid <= 0;
                                else
                                    b_valid <= 0;
                            end
                            else begin
                                operand_done <= 1;

                                if (!selected_matrix)
                                    a_valid <= 1;
                                else begin
                                    b_valid <= 1;
                                    pair_valid <= a_valid;
                                end
                            end

                            state <= IDLE;
                        end
                    end
                end

                DRAIN: begin
                    // Discard remaining DMA output without writing matrix
                    // storage. Finish only after TLAST is accepted.
                    if (stream_fire && s_axis_tlast) begin
                        operand_error <= 1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 DMA
 */
