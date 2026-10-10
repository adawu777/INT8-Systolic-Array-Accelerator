// ============================================================
// 9. MATRIX ACCELERATOR V4 TOP
// ============================================================

module matrix_accelerator_v4_top #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst_n,
    input logic start,

    output logic busy,
    output logic done,

    input logic a_wr_en,
    input logic [1:0] a_wr_bank,
    input logic [1:0] a_wr_addr,
    input logic signed [DATA_W-1:0] a_wr_data,

    input logic b_wr_en,
    input logic [1:0] b_wr_bank,
    input logic [1:0] b_wr_addr,
    input logic signed [DATA_W-1:0] b_wr_data,

    input logic [3:0] c_rd_addr,
    output logic signed [ACC_W-1:0] c_rd_data
);

    logic compute_start;
    logic compute_busy;
    logic compute_done;

    logic writeback_start;
    logic writeback_busy;
    logic writeback_done;

    logic [16*ACC_W-1:0] c_matrix;

    logic c_wr_en;
    logic [3:0] c_wr_addr;
    logic signed [ACC_W-1:0] c_wr_data;

    typedef enum logic [1:0] {
        IDLE, COMPUTE, WRITEBACK, DONE
    } state_t;

    state_t state;

    logic compute_started;
    logic writeback_started;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
        end
        else begin
            case (state)
                IDLE: begin
                    if (start)
                        state <= COMPUTE;
                end

                COMPUTE: begin
                    if (compute_done)
                        state <= WRITEBACK;
                end

                WRITEBACK: begin
                    if (writeback_done)
                        state <= DONE;
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            compute_started <= 0;
            writeback_started <= 0;
        end
        else begin
            if (state != COMPUTE)
                compute_started <= 0;
            else
                compute_started <= 1;

            if (state != WRITEBACK)
                writeback_started <= 0;
            else
                writeback_started <= 1;
        end
    end

    assign compute_start =
        (state == COMPUTE) && !compute_started;

    assign writeback_start =
        (state == WRITEBACK) && !writeback_started;

    assign busy =
        (state == COMPUTE) || (state == WRITEBACK);

    assign done = (state == DONE);

    matrix_compute_top #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_compute (
        .clk(clk),
        .rst_n(rst_n),
        .start(compute_start),

        .a_wr_en(a_wr_en),
        .a_wr_bank(a_wr_bank),
        .a_wr_addr(a_wr_addr),
        .a_wr_data(a_wr_data),

        .b_wr_en(b_wr_en),
        .b_wr_bank(b_wr_bank),
        .b_wr_addr(b_wr_addr),
        .b_wr_data(b_wr_data),

        .busy(compute_busy),
        .compute_done(compute_done),
        .c_matrix(c_matrix)
    );

    c_writeback_controller #(
        .ACC_W(ACC_W)
    ) u_writeback (
        .clk(clk),
        .rst_n(rst_n),
        .start(writeback_start),
        .c_matrix(c_matrix),

        .busy(writeback_busy),
        .writeback_done(writeback_done),

        .sram_wr_en(c_wr_en),
        .sram_wr_addr(c_wr_addr),
        .sram_wr_data(c_wr_data)
    );

    output_sram #(
        .DATA_W(ACC_W),
        .DEPTH(16)
    ) u_output_sram (
        .clk(clk),
        .wr_en(c_wr_en),
        .wr_addr(c_wr_addr),
        .wr_data(c_wr_data),
        .rd_addr(c_rd_addr),
        .rd_data(c_rd_data)
    );

endmodule


`timescale 1ns/1ps
