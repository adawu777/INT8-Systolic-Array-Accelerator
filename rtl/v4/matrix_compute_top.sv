// ============================================================
// 6. MATRIX COMPUTE TOP
// ============================================================

module matrix_compute_top #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst_n,
    input logic start,

    input logic a_wr_en,
    input logic [1:0] a_wr_bank,
    input logic [1:0] a_wr_addr,
    input logic signed [DATA_W-1:0] a_wr_data,

    input logic b_wr_en,
    input logic [1:0] b_wr_bank,
    input logic [1:0] b_wr_addr,
    input logic signed [DATA_W-1:0] b_wr_data,

    output logic busy,
    output logic compute_done,
    output logic [16*ACC_W-1:0] c_matrix
);

    logic [1:0] rd_addr;

    logic [4*DATA_W-1:0] a_sram_data;
    logic [4*DATA_W-1:0] b_sram_data;

    logic [4*DATA_W-1:0] a_vector;
    logic [4*DATA_W-1:0] b_vector;

    logic [4*DATA_W-1:0] a_skewed;
    logic [4*DATA_W-1:0] b_skewed;

    logic [3:0] a_valid;
    logic [3:0] b_valid;

    logic reader_valid;
    logic reader_busy;
    logic reader_done;
    logic reader_start;
    logic clear_acc;

    typedef enum logic [1:0] {
        IDLE, CLEAR, RUN, FINISH
    } compute_state_t;

    compute_state_t state;
    logic [3:0] drain_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            drain_count <= 0;
            compute_done <= 0;
        end
        else begin
            compute_done <= 0;

            case (state)
                IDLE: begin
                    drain_count <= 0;
                    if (start)
                        state <= CLEAR;
                end

                CLEAR: begin
                    state <= RUN;
                end

                RUN: begin
                    if (reader_done) begin
                        drain_count <= 0;
                        state <= FINISH;
                    end
                end

                FINISH: begin
                    if (drain_count == 4'd8) begin
                        compute_done <= 1;
                        state <= IDLE;
                    end
                    else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign clear_acc = (state == CLEAR);
    assign reader_start = (state == CLEAR);
    assign busy = (state != IDLE);

    banked_sram #(.DATA_W(DATA_W)) u_a_sram (
        .clk(clk),
        .wr_en(a_wr_en),
        .wr_bank(a_wr_bank),
        .wr_addr(a_wr_addr),
        .wr_data(a_wr_data),
        .rd_addr(rd_addr),
        .rd_data(a_sram_data)
    );

    banked_sram #(.DATA_W(DATA_W)) u_b_sram (
        .clk(clk),
        .wr_en(b_wr_en),
        .wr_bank(b_wr_bank),
        .wr_addr(b_wr_addr),
        .wr_data(b_wr_data),
        .rd_addr(rd_addr),
        .rd_data(b_sram_data)
    );

    matrix_sram_reader #(.DATA_W(DATA_W)) u_reader (
        .clk(clk),
        .rst_n(rst_n),
        .start(reader_start),
        .busy(reader_busy),
        .done(reader_done),
        .rd_addr(rd_addr),
        .a_sram_data(a_sram_data),
        .b_sram_data(b_sram_data),
        .a_vector(a_vector),
        .b_vector(b_vector),
        .out_valid(reader_valid)
    );

    input_skew_4x4 #(.DATA_W(DATA_W)) u_skew (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(reader_valid),
        .a_vector(a_vector),
        .b_vector(b_vector),
        .a_skewed(a_skewed),
        .b_skewed(b_skewed),
        .a_valid(a_valid),
        .b_valid(b_valid)
    );

    systolic_array_4x4 #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),
        .a_skewed(a_skewed),
        .b_skewed(b_skewed),
        .a_valid(a_valid),
        .b_valid(b_valid),
        .c_matrix(c_matrix)
    );

endmodule


// ============================================================
// 7. OUTPUT SRAM
// ============================================================
