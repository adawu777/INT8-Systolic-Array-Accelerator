// ============================================================
// 2. MATRIX SRAM READER
// ============================================================

module matrix_sram_reader #(
    parameter int DATA_W = 8
)(
    input logic clk,
    input logic rst_n,
    input logic start,
    output logic busy,
    output logic done,
    output logic [1:0] rd_addr,
    input logic [4*DATA_W-1:0] a_sram_data,
    input logic [4*DATA_W-1:0] b_sram_data,
    output logic [4*DATA_W-1:0] a_vector,
    output logic [4*DATA_W-1:0] b_vector,
    output logic out_valid
);

    typedef enum logic [1:0] {
        IDLE, ISSUE, DRAIN
    } state_t;

    state_t state;
    logic [1:0] k_counter;
    logic read_valid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            k_counter <= 0;
            read_valid <= 0;
            done <= 0;
        end
        else begin
            done <= 0;

            case (state)
                IDLE: begin
                    k_counter <= 0;
                    read_valid <= 0;
                    if (start)
                        state <= ISSUE;
                end

                ISSUE: begin
                    read_valid <= 1;
                    if (k_counter == 3)
                        state <= DRAIN;
                    else
                        k_counter <= k_counter + 1'b1;
                end

                DRAIN: begin
                    read_valid <= 0;
                    done <= 1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    k_counter <= 0;
                    read_valid <= 0;
                end
            endcase
        end
    end

    assign rd_addr = k_counter;
    assign a_vector = a_sram_data;
    assign b_vector = b_sram_data;
    assign out_valid = read_valid;
    assign busy = (state != IDLE);

endmodule


// ============================================================
// 3. INPUT SKEW 4x4
// ============================================================
