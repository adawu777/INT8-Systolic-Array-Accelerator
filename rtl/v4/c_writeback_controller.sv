// ============================================================
// 8. C WRITEBACK CONTROLLER
// ============================================================

module c_writeback_controller #(
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst_n,
    input logic start,

    input logic [16*ACC_W-1:0] c_matrix,

    output logic busy,
    output logic writeback_done,

    output logic sram_wr_en,
    output logic [3:0] sram_wr_addr,
    output logic signed [ACC_W-1:0] sram_wr_data
);

    typedef enum logic [1:0] {
        IDLE, WRITE, FINISH
    } state_t;

    state_t state;
    logic [3:0] write_index;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            write_index <= 0;
            writeback_done <= 0;
        end
        else begin
            writeback_done <= 0;

            case (state)
                IDLE: begin
                    write_index <= 0;
                    if (start)
                        state <= WRITE;
                end

                WRITE: begin
                    if (write_index == 15)
                        state <= FINISH;
                    else
                        write_index <= write_index + 1'b1;
                end

                FINISH: begin
                    writeback_done <= 1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    write_index <= 0;
                end
            endcase
        end
    end

    always_comb begin
        busy = (state != IDLE);

        sram_wr_en = 0;
        sram_wr_addr = 0;
        sram_wr_data = '0;

        if (state == WRITE) begin
            sram_wr_en = 1;
            sram_wr_addr = write_index;
            sram_wr_data =
                $signed(c_matrix[write_index*ACC_W +: ACC_W]);
        end
    end

endmodule


// ============================================================
// 9. MATRIX ACCELERATOR V4 TOP
// ============================================================
