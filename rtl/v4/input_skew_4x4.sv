// ============================================================
// 3. INPUT SKEW 4x4
// ============================================================

module input_skew_4x4 #(
    parameter int DATA_W = 8
)(
    input logic clk,
    input logic rst_n,
    input logic in_valid,
    input logic [4*DATA_W-1:0] a_vector,
    input logic [4*DATA_W-1:0] b_vector,
    output logic [4*DATA_W-1:0] a_skewed,
    output logic [4*DATA_W-1:0] b_skewed,
    output logic [3:0] a_valid,
    output logic [3:0] b_valid
);

    logic [DATA_W-1:0] a_pipe1 [0:0];
    logic [DATA_W-1:0] a_pipe2 [0:1];
    logic [DATA_W-1:0] a_pipe3 [0:2];

    logic [DATA_W-1:0] b_pipe1 [0:0];
    logic [DATA_W-1:0] b_pipe2 [0:1];
    logic [DATA_W-1:0] b_pipe3 [0:2];

    logic [2:0] valid_pipe;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_skewed <= '0;
            b_skewed <= '0;
            a_valid <= '0;
            b_valid <= '0;
            valid_pipe <= '0;

            for (int i=0; i<1; i++) begin
                a_pipe1[i] <= '0;
                b_pipe1[i] <= '0;
            end

            for (int i=0; i<2; i++) begin
                a_pipe2[i] <= '0;
                b_pipe2[i] <= '0;
            end

            for (int i=0; i<3; i++) begin
                a_pipe3[i] <= '0;
                b_pipe3[i] <= '0;
            end
        end
        else begin
            a_skewed[0*DATA_W +: DATA_W]
                <= a_vector[0*DATA_W +: DATA_W];
            b_skewed[0*DATA_W +: DATA_W]
                <= b_vector[0*DATA_W +: DATA_W];

            a_pipe1[0] <= a_vector[1*DATA_W +: DATA_W];
            b_pipe1[0] <= b_vector[1*DATA_W +: DATA_W];

            a_skewed[1*DATA_W +: DATA_W] <= a_pipe1[0];
            b_skewed[1*DATA_W +: DATA_W] <= b_pipe1[0];

            a_pipe2[0] <= a_vector[2*DATA_W +: DATA_W];
            a_pipe2[1] <= a_pipe2[0];

            b_pipe2[0] <= b_vector[2*DATA_W +: DATA_W];
            b_pipe2[1] <= b_pipe2[0];

            a_skewed[2*DATA_W +: DATA_W] <= a_pipe2[1];
            b_skewed[2*DATA_W +: DATA_W] <= b_pipe2[1];

            a_pipe3[0] <= a_vector[3*DATA_W +: DATA_W];
            a_pipe3[1] <= a_pipe3[0];
            a_pipe3[2] <= a_pipe3[1];

            b_pipe3[0] <= b_vector[3*DATA_W +: DATA_W];
            b_pipe3[1] <= b_pipe3[0];
            b_pipe3[2] <= b_pipe3[1];

            a_skewed[3*DATA_W +: DATA_W] <= a_pipe3[2];
            b_skewed[3*DATA_W +: DATA_W] <= b_pipe3[2];

            valid_pipe[0] <= in_valid;
            valid_pipe[1] <= valid_pipe[0];
            valid_pipe[2] <= valid_pipe[1];

            a_valid[0] <= in_valid;
            a_valid[1] <= valid_pipe[0];
            a_valid[2] <= valid_pipe[1];
            a_valid[3] <= valid_pipe[2];

            b_valid[0] <= in_valid;
            b_valid[1] <= valid_pipe[0];
            b_valid[2] <= valid_pipe[1];
            b_valid[3] <= valid_pipe[2];
        end
    end

endmodule


// ============================================================
// 4. SYSTOLIC PE
// ============================================================
