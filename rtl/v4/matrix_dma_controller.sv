`timescale 1ns/1ps
module matrix_dma_controller (
    input  wire        clk,
    input  wire        rst_n,

    // -----------------------------------------
    // Job Command Interface
    // -----------------------------------------
    input  wire        start,
    input  wire [31:0] a_base_addr,
    input  wire [31:0] b_base_addr,

    // -----------------------------------------
    // AXI DMA Descriptor Interface
    // -----------------------------------------
    output wire [31:0] desc_addr,
    output wire [19:0] desc_len,
    output wire [7:0]  desc_tag,
    output wire        desc_valid,
    input  wire        desc_ready,

    // -----------------------------------------
    // Staging Adapter Control
    // -----------------------------------------
    output wire        staging_start,
    output wire        matrix_sel,

    input  wire        operand_done,
    input  wire        operand_error,

    // -----------------------------------------
    // Job Status
    // -----------------------------------------
    output wire        busy,
    output reg         done,
    output reg         error
);

    // =========================================
    // FSM State Definitions
    // =========================================

    localparam [2:0]
        ST_IDLE    = 3'd0,
        ST_START_A = 3'd1,
        ST_DESC_A  = 3'd2,
        ST_WAIT_A  = 3'd3,
        ST_START_B = 3'd4,
        ST_DESC_B  = 3'd5,
        ST_WAIT_B  = 3'd6;

    reg [2:0] state;

    // =========================================
    // Address Registers
    // =========================================

    reg [31:0] a_addr_reg;
    reg [31:0] b_addr_reg;

    // =========================================
    // Output Logic
    // =========================================

    assign busy = (state != ST_IDLE);

    // 0 = Matrix A
    // 1 = Matrix B
    assign matrix_sel =
        (state == ST_START_B) ||
        (state == ST_DESC_B)  ||
        (state == ST_WAIT_B);

    // Start Staging Adapter before issuing
    // the corresponding DMA descriptor.
    assign staging_start =
        (state == ST_START_A) ||
        (state == ST_START_B);

    // DMA descriptor fields
    assign desc_addr =
        matrix_sel ? b_addr_reg : a_addr_reg;

    // 4x4 INT8 matrix:
    // 16 elements x 1 byte = 16 bytes
    assign desc_len = 20'd16;

    // Descriptor tags
    assign desc_tag =
        matrix_sel ? 8'hB1 : 8'hA1;

    // Hold VALID until READY handshake
    assign desc_valid =
        (state == ST_DESC_A) ||
        (state == ST_DESC_B);

    // =========================================
    // Sequential FSM
    // =========================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;

            a_addr_reg <= 32'd0;
            b_addr_reg <= 32'd0;

            done  <= 1'b0;
            error <= 1'b0;
        end
        else begin

            // One-cycle status pulses
            done  <= 1'b0;
            error <= 1'b0;

            case (state)

                // ---------------------------------
                // IDLE
                // ---------------------------------
                ST_IDLE: begin
                    if (start) begin
                        a_addr_reg <= a_base_addr;
                        b_addr_reg <= b_base_addr;

                        state <= ST_START_A;
                    end
                end

                // ---------------------------------
                // Arm Matrix A Staging
                // ---------------------------------
                ST_START_A: begin
                    state <= ST_DESC_A;
                end

                // ---------------------------------
                // Issue Matrix A DMA Descriptor
                // ---------------------------------
                ST_DESC_A: begin
                    if (desc_valid && desc_ready)
                        state <= ST_WAIT_A;
                end

                // ---------------------------------
                // Wait for Matrix A Completion
                // ---------------------------------
                ST_WAIT_A: begin
                    if (operand_error) begin
                        error <= 1'b1;
                        state <= ST_IDLE;
                    end
                    else if (operand_done) begin
                        state <= ST_START_B;
                    end
                end

                // ---------------------------------
                // Arm Matrix B Staging
                // ---------------------------------
                ST_START_B: begin
                    state <= ST_DESC_B;
                end

                // ---------------------------------
                // Issue Matrix B DMA Descriptor
                // ---------------------------------
                ST_DESC_B: begin
                    if (desc_valid && desc_ready)
                        state <= ST_WAIT_B;
                end

                // ---------------------------------
                // Wait for Matrix B Completion
                // ---------------------------------
                ST_WAIT_B: begin
                    if (operand_error) begin
                        error <= 1'b1;
                        state <= ST_IDLE;
                    end
                    else if (operand_done) begin
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule




// Step 9F: SRAM writeback after successful A/B staging
`timescale 1ns/1ps
