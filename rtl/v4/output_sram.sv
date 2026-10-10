// ============================================================
// 7. OUTPUT SRAM
// ============================================================

module output_sram #(
    parameter int DATA_W = 32,
    parameter int DEPTH = 16,
    parameter int ADDR_W = $clog2(DEPTH)
)(
    input logic clk,

    input logic wr_en,
    input logic [ADDR_W-1:0] wr_addr,
    input logic signed [DATA_W-1:0] wr_data,

    input logic [ADDR_W-1:0] rd_addr,
    output logic signed [DATA_W-1:0] rd_data
);

    logic signed [DATA_W-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule


// ============================================================
// 8. C WRITEBACK CONTROLLER
// ============================================================
