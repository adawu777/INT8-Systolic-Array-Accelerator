// Step 8B compute datapath (preserved)


// ============================================================
// 1. BANKED SRAM
// ============================================================

module banked_sram #(
    parameter int DATA_W = 8,
    parameter int NUM_BANKS = 4,
    parameter int BANK_DEPTH = 4,
    parameter int BANK_W = $clog2(NUM_BANKS),
    parameter int ADDR_W = $clog2(BANK_DEPTH)
)(
    input logic clk,
    input logic wr_en,
    input logic [BANK_W-1:0] wr_bank,
    input logic [ADDR_W-1:0] wr_addr,
    input logic signed [DATA_W-1:0] wr_data,
    input logic [ADDR_W-1:0] rd_addr,
    output logic [NUM_BANKS*DATA_W-1:0] rd_data
);

    logic signed [DATA_W-1:0]
        mem [0:NUM_BANKS-1][0:BANK_DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_bank][wr_addr] <= wr_data;
    end

    always_ff @(posedge clk) begin
        rd_data[0*DATA_W +: DATA_W] <= mem[0][rd_addr];
        rd_data[1*DATA_W +: DATA_W] <= mem[1][rd_addr];
        rd_data[2*DATA_W +: DATA_W] <= mem[2][rd_addr];
        rd_data[3*DATA_W +: DATA_W] <= mem[3][rd_addr];
    end

endmodule


// ============================================================
// 2. MATRIX SRAM READER
// ============================================================
