// ============================================================
// 4. SYSTOLIC PE
// ============================================================

module systolic_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst_n,
    input logic clear_acc,

    input logic signed [DATA_W-1:0] a_in,
    input logic signed [DATA_W-1:0] b_in,
    input logic a_valid_in,
    input logic b_valid_in,

    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic a_valid_out,
    output logic b_valid_out,

    output logic signed [ACC_W-1:0] acc_out
);

    logic signed [2*DATA_W-1:0] product;

    assign product = a_in * b_in;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_out <= '0;
            b_out <= '0;
            a_valid_out <= 0;
            b_valid_out <= 0;
            acc_out <= '0;
        end
        else if (clear_acc) begin
            a_out <= '0;
            b_out <= '0;
            a_valid_out <= 0;
            b_valid_out <= 0;
            acc_out <= '0;
        end
        else begin
            a_out <= a_in;
            b_out <= b_in;

            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;

            if (a_valid_in && b_valid_in)
                acc_out <= acc_out + product;
        end
    end

endmodule


// ============================================================
// 5. SYSTOLIC ARRAY 4x4
// ============================================================
