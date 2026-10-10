// ============================================================
// 5. SYSTOLIC ARRAY 4x4
// ============================================================

module systolic_array_4x4 #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst_n,
    input logic clear_acc,

    input logic [4*DATA_W-1:0] a_skewed,
    input logic [4*DATA_W-1:0] b_skewed,
    input logic [3:0] a_valid,
    input logic [3:0] b_valid,

    output wire [16*ACC_W-1:0] c_matrix
);

    wire signed [DATA_W-1:0] a_link [0:3][0:4];
    wire signed [DATA_W-1:0] b_link [0:4][0:3];

    wire a_vlink [0:3][0:4];
    wire b_vlink [0:4][0:3];

    genvar r, c;

    generate
        for (r=0; r<4; r=r+1) begin : A_INPUT
            assign a_link[r][0] =
                $signed(a_skewed[r*DATA_W +: DATA_W]);
            assign a_vlink[r][0] = a_valid[r];
        end

        for (c=0; c<4; c=c+1) begin : B_INPUT
            assign b_link[0][c] =
                $signed(b_skewed[c*DATA_W +: DATA_W]);
            assign b_vlink[0][c] = b_valid[c];
        end

        for (r=0; r<4; r=r+1) begin : ROWS
            for (c=0; c<4; c=c+1) begin : COLS

                systolic_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear_acc(clear_acc),

                    .a_in(a_link[r][c]),
                    .b_in(b_link[r][c]),

                    .a_valid_in(a_vlink[r][c]),
                    .b_valid_in(b_vlink[r][c]),

                    .a_out(a_link[r][c+1]),
                    .b_out(b_link[r+1][c]),

                    .a_valid_out(a_vlink[r][c+1]),
                    .b_valid_out(b_vlink[r+1][c]),

                    .acc_out(
                        c_matrix[(r*4+c)*ACC_W +: ACC_W]
                    )
                );

            end
        end
    endgenerate

endmodule


// ============================================================
// 6. MATRIX COMPUTE TOP
// ============================================================
