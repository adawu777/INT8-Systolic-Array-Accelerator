
`timescale 1ns/1ps

module matrix_dma_staging_v2 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire        matrix_sel,
    output wire        cmd_ready,
    output wire        busy,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    input  wire        dma_status_valid,
    input  wire [7:0]  dma_status_tag,
    input  wire [3:0]  dma_status_error,

    output reg         operand_done,
    output reg         operand_error,
    output reg         pair_valid,

    input  wire [3:0]  rd_index,
    output wire [7:0]  a_rd_data,
    output wire [7:0]  b_rd_data
);

    localparam [1:0] IDLE = 2'd0, ACTIVE = 2'd1, DRAIN = 2'd2;

    reg [1:0] state;
    reg selected_matrix;
    reg [7:0] expected_tag;

    reg [2:0] beat_count;
    reg stream_complete;
    reg frame_error;

    reg status_seen;
    reg status_failed;

    reg a_valid;
    reg b_valid;

    reg [7:0] a_mem [0:15];
    reg [7:0] b_mem [0:15];

    wire stream_fire =
        s_axis_tvalid && s_axis_tready;

    wire status_fire =
        dma_status_valid && (state == ACTIVE);

    wire status_bad_now =
        (dma_status_tag != expected_tag) ||
        (dma_status_error != 4'd0);

    wire status_available =
        status_seen || status_fire;

    wire status_bad =
        status_failed ||
        (status_fire && status_bad_now);

    wire frame_done_now =
        stream_fire && (beat_count == 3);

    wire frame_bad_now =
        stream_fire &&
        ((s_axis_tkeep != 4'hF) ||
         (s_axis_tlast != (beat_count == 3)));

    wire data_complete =
        stream_complete || frame_done_now;

    wire data_bad =
        frame_error || frame_bad_now;

    assign cmd_ready = (state == IDLE);
    assign busy = (state != IDLE);

    assign s_axis_tready =
        ((state == ACTIVE) && !stream_complete &&
         (beat_count < 4) && !status_failed) ||
        (state == DRAIN);

    assign a_rd_data = a_mem[rd_index];
    assign b_rd_data = b_mem[rd_index];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            selected_matrix <= 0;
            expected_tag <= 0;

            beat_count <= 0;
            stream_complete <= 0;
            frame_error <= 0;

            status_seen <= 0;
            status_failed <= 0;

            a_valid <= 0;
            b_valid <= 0;
            pair_valid <= 0;

            operand_done <= 0;
            operand_error <= 0;

            for (i = 0; i < 16; i = i + 1) begin
                a_mem[i] <= 0;
                b_mem[i] <= 0;
            end
        end
        else begin
            operand_done <= 0;
            operand_error <= 0;

            case (state)
                IDLE: begin
                    if (start) begin
                        if (matrix_sel && !a_valid) begin
                            operand_error <= 1;
                        end
                        else begin
                            selected_matrix <= matrix_sel;

                            expected_tag <=
                                matrix_sel ? 8'hB1 : 8'hA1;

                            beat_count <= 0;
                            stream_complete <= 0;
                            frame_error <= 0;

                            status_seen <= 0;
                            status_failed <= 0;

                            if (!matrix_sel) begin
                                a_valid <= 0;
                                b_valid <= 0;
                                pair_valid <= 0;
                            end

                            state <= ACTIVE;
                        end
                    end
                end

                ACTIVE: begin
                    if (status_fire) begin
                        status_seen <= 1;

                        if (status_bad_now)
                            status_failed <= 1;
                    end

                    if (stream_fire) begin
                        if (!selected_matrix) begin
                            a_mem[beat_count*4+0]
                                <= s_axis_tdata[7:0];
                            a_mem[beat_count*4+1]
                                <= s_axis_tdata[15:8];
                            a_mem[beat_count*4+2]
                                <= s_axis_tdata[23:16];
                            a_mem[beat_count*4+3]
                                <= s_axis_tdata[31:24];
                        end
                        else begin
                            b_mem[beat_count*4+0]
                                <= s_axis_tdata[7:0];
                            b_mem[beat_count*4+1]
                                <= s_axis_tdata[15:8];
                            b_mem[beat_count*4+2]
                                <= s_axis_tdata[23:16];
                            b_mem[beat_count*4+3]
                                <= s_axis_tdata[31:24];
                        end

                        if (frame_bad_now)
                            frame_error <= 1;

                        beat_count <= beat_count + 1'b1;

                        if (beat_count == 3)
                            stream_complete <= 1;
                    end

                    if (status_available) begin
                        if (status_bad) begin
                            pair_valid <= 0;

                            if (!selected_matrix)
                                a_valid <= 0;
                            else
                                b_valid <= 0;

                            // Do not release this job until all output
                            // stream beats have been consumed. DMA status
                            // can precede the final AXI-Stream handshake.
                            if (stream_complete ||
                                (stream_fire && s_axis_tlast)) begin
                                operand_error <= 1;
                                state <= IDLE;
                            end
                            else begin
                                state <= DRAIN;
                            end
                        end
                        else if (data_complete) begin
                            if (data_bad) begin
                                operand_error <= 1;
                                pair_valid <= 0;

                                if (!selected_matrix)
                                    a_valid <= 0;
                                else
                                    b_valid <= 0;
                            end
                            else begin
                                operand_done <= 1;

                                if (!selected_matrix)
                                    a_valid <= 1;
                                else begin
                                    b_valid <= 1;
                                    pair_valid <= a_valid;
                                end
                            end

                            state <= IDLE;
                        end
                    end
                end

                DRAIN: begin
                    // Discard remaining DMA output without writing matrix
                    // storage. Finish only after TLAST is accepted.
                    if (stream_fire && s_axis_tlast) begin
                        operand_error <= 1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 DMA
 */
module axi_dma_rd #
(
    // Width of AXI data bus in bits
    parameter AXI_DATA_WIDTH = 32,
    // Width of AXI address bus in bits
    parameter AXI_ADDR_WIDTH = 16,
    // Width of AXI wstrb (width of data bus in words)
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8),
    // Width of AXI ID signal
    parameter AXI_ID_WIDTH = 8,
    // Maximum AXI burst length to generate
    parameter AXI_MAX_BURST_LEN = 16,
    // Width of AXI stream interfaces in bits
    parameter AXIS_DATA_WIDTH = AXI_DATA_WIDTH,
    // Use AXI stream tkeep signal
    parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
    // AXI stream tkeep signal width (words per cycle)
    parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
    // Use AXI stream tlast signal
    parameter AXIS_LAST_ENABLE = 1,
    // Propagate AXI stream tid signal
    parameter AXIS_ID_ENABLE = 0,
    // AXI stream tid signal width
    parameter AXIS_ID_WIDTH = 8,
    // Propagate AXI stream tdest signal
    parameter AXIS_DEST_ENABLE = 0,
    // AXI stream tdest signal width
    parameter AXIS_DEST_WIDTH = 8,
    // Propagate AXI stream tuser signal
    parameter AXIS_USER_ENABLE = 1,
    // AXI stream tuser signal width
    parameter AXIS_USER_WIDTH = 1,
    // Width of length field
    parameter LEN_WIDTH = 20,
    // Width of tag field
    parameter TAG_WIDTH = 8,
    // Enable support for scatter/gather DMA
    // (multiple descriptors per AXI stream frame)
    parameter ENABLE_SG = 0,
    // Enable support for unaligned transfers
    parameter ENABLE_UNALIGNED = 0
)
(
    input  wire                       clk,
    input  wire                       rst,

    /*
     * AXI read descriptor input
     */
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axis_read_desc_addr,
    input  wire [LEN_WIDTH-1:0]       s_axis_read_desc_len,
    input  wire [TAG_WIDTH-1:0]       s_axis_read_desc_tag,
    input  wire [AXIS_ID_WIDTH-1:0]   s_axis_read_desc_id,
    input  wire [AXIS_DEST_WIDTH-1:0] s_axis_read_desc_dest,
    input  wire [AXIS_USER_WIDTH-1:0] s_axis_read_desc_user,
    input  wire                       s_axis_read_desc_valid,
    output wire                       s_axis_read_desc_ready,

    /*
     * AXI read descriptor status output
     */
    output wire [TAG_WIDTH-1:0]       m_axis_read_desc_status_tag,
    output wire [3:0]                 m_axis_read_desc_status_error,
    output wire                       m_axis_read_desc_status_valid,

    /*
     * AXI stream read data output
     */
    output wire [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep,
    output wire                       m_axis_read_data_tvalid,
    input  wire                       m_axis_read_data_tready,
    output wire                       m_axis_read_data_tlast,
    output wire [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid,
    output wire [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest,
    output wire [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser,

    /*
     * AXI master interface
     */
    output wire [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arlock,
    output wire [3:0]                 m_axi_arcache,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready,

    /*
     * Configuration
     */
    input  wire                       enable
);

parameter AXI_WORD_WIDTH = AXI_STRB_WIDTH;
parameter AXI_WORD_SIZE = AXI_DATA_WIDTH/AXI_WORD_WIDTH;
parameter AXI_BURST_SIZE = $clog2(AXI_STRB_WIDTH);
parameter AXI_MAX_BURST_SIZE = AXI_MAX_BURST_LEN << AXI_BURST_SIZE;

parameter AXIS_KEEP_WIDTH_INT = AXIS_KEEP_ENABLE ? AXIS_KEEP_WIDTH : 1;
parameter AXIS_WORD_WIDTH = AXIS_KEEP_WIDTH_INT;
parameter AXIS_WORD_SIZE = AXIS_DATA_WIDTH/AXIS_WORD_WIDTH;

parameter OFFSET_WIDTH = AXI_STRB_WIDTH > 1 ? $clog2(AXI_STRB_WIDTH) : 1;
parameter OFFSET_MASK = AXI_STRB_WIDTH > 1 ? {OFFSET_WIDTH{1'b1}} : 0;
parameter ADDR_MASK = {AXI_ADDR_WIDTH{1'b1}} << $clog2(AXI_STRB_WIDTH);
parameter CYCLE_COUNT_WIDTH = LEN_WIDTH - AXI_BURST_SIZE + 1;

parameter OUTPUT_FIFO_ADDR_WIDTH = 5;

// bus width assertions
initial begin
    if (AXI_WORD_SIZE * AXI_STRB_WIDTH != AXI_DATA_WIDTH) begin
        $error("Error: AXI data width not evenly divisble (instance %m)");
        $finish;
    end

    if (AXIS_WORD_SIZE * AXIS_KEEP_WIDTH_INT != AXIS_DATA_WIDTH) begin
        $error("Error: AXI stream data width not evenly divisble (instance %m)");
        $finish;
    end

    if (AXI_WORD_SIZE != AXIS_WORD_SIZE) begin
        $error("Error: word size mismatch (instance %m)");
        $finish;
    end

    if (2**$clog2(AXI_WORD_WIDTH) != AXI_WORD_WIDTH) begin
        $error("Error: AXI word width must be even power of two (instance %m)");
        $finish;
    end

    if (AXI_DATA_WIDTH != AXIS_DATA_WIDTH) begin
        $error("Error: AXI interface width must match AXI stream interface width (instance %m)");
        $finish;
    end

    if (AXI_MAX_BURST_LEN < 1 || AXI_MAX_BURST_LEN > 256) begin
        $error("Error: AXI_MAX_BURST_LEN must be between 1 and 256 (instance %m)");
        $finish;
    end

    if (ENABLE_SG) begin
        $error("Error: scatter/gather is not yet implemented (instance %m)");
        $finish;
    end
end

localparam [1:0]
    AXI_RESP_OKAY = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11;

localparam [3:0]
    DMA_ERROR_NONE = 4'd0,
    DMA_ERROR_TIMEOUT = 4'd1,
    DMA_ERROR_PARITY = 4'd2,
    DMA_ERROR_AXI_RD_SLVERR = 4'd4,
    DMA_ERROR_AXI_RD_DECERR = 4'd5,
    DMA_ERROR_AXI_WR_SLVERR = 4'd6,
    DMA_ERROR_AXI_WR_DECERR = 4'd7,
    DMA_ERROR_PCIE_FLR = 4'd8,
    DMA_ERROR_PCIE_CPL_POISONED = 4'd9,
    DMA_ERROR_PCIE_CPL_STATUS_UR = 4'd10,
    DMA_ERROR_PCIE_CPL_STATUS_CA = 4'd11;

localparam [0:0]
    AXI_STATE_IDLE = 1'd0,
    AXI_STATE_START = 1'd1;

reg [0:0] axi_state_reg = AXI_STATE_IDLE, axi_state_next;

localparam [0:0]
    AXIS_STATE_IDLE = 1'd0,
    AXIS_STATE_READ = 1'd1;

reg [0:0] axis_state_reg = AXIS_STATE_IDLE, axis_state_next;

// datapath control signals
reg transfer_in_save;
reg axis_cmd_ready;

reg [AXI_ADDR_WIDTH-1:0] addr_reg = {AXI_ADDR_WIDTH{1'b0}}, addr_next;
reg [LEN_WIDTH-1:0] op_word_count_reg = {LEN_WIDTH{1'b0}}, op_word_count_next;
reg [LEN_WIDTH-1:0] tr_word_count_reg = {LEN_WIDTH{1'b0}}, tr_word_count_next;

reg [OFFSET_WIDTH-1:0] axis_cmd_offset_reg = {OFFSET_WIDTH{1'b0}}, axis_cmd_offset_next;
reg [OFFSET_WIDTH-1:0] axis_cmd_last_cycle_offset_reg = {OFFSET_WIDTH{1'b0}}, axis_cmd_last_cycle_offset_next;
reg [CYCLE_COUNT_WIDTH-1:0] axis_cmd_input_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, axis_cmd_input_cycle_count_next;
reg [CYCLE_COUNT_WIDTH-1:0] axis_cmd_output_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, axis_cmd_output_cycle_count_next;
reg axis_cmd_bubble_cycle_reg = 1'b0, axis_cmd_bubble_cycle_next;
reg [TAG_WIDTH-1:0] axis_cmd_tag_reg = {TAG_WIDTH{1'b0}}, axis_cmd_tag_next;
reg [AXIS_ID_WIDTH-1:0] axis_cmd_axis_id_reg = {AXIS_ID_WIDTH{1'b0}}, axis_cmd_axis_id_next;
reg [AXIS_DEST_WIDTH-1:0] axis_cmd_axis_dest_reg = {AXIS_DEST_WIDTH{1'b0}}, axis_cmd_axis_dest_next;
reg [AXIS_USER_WIDTH-1:0] axis_cmd_axis_user_reg = {AXIS_USER_WIDTH{1'b0}}, axis_cmd_axis_user_next;
reg axis_cmd_valid_reg = 1'b0, axis_cmd_valid_next;

reg [OFFSET_WIDTH-1:0] offset_reg = {OFFSET_WIDTH{1'b0}}, offset_next;
reg [OFFSET_WIDTH-1:0] last_cycle_offset_reg = {OFFSET_WIDTH{1'b0}}, last_cycle_offset_next;
reg [CYCLE_COUNT_WIDTH-1:0] input_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, input_cycle_count_next;
reg [CYCLE_COUNT_WIDTH-1:0] output_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, output_cycle_count_next;
reg input_active_reg = 1'b0, input_active_next;
reg output_active_reg = 1'b0, output_active_next;
reg bubble_cycle_reg = 1'b0, bubble_cycle_next;
reg first_cycle_reg = 1'b0, first_cycle_next;
reg output_last_cycle_reg = 1'b0, output_last_cycle_next;
reg [1:0] rresp_reg = AXI_RESP_OKAY, rresp_next;

reg [TAG_WIDTH-1:0] tag_reg = {TAG_WIDTH{1'b0}}, tag_next;
reg [AXIS_ID_WIDTH-1:0] axis_id_reg = {AXIS_ID_WIDTH{1'b0}}, axis_id_next;
reg [AXIS_DEST_WIDTH-1:0] axis_dest_reg = {AXIS_DEST_WIDTH{1'b0}}, axis_dest_next;
reg [AXIS_USER_WIDTH-1:0] axis_user_reg = {AXIS_USER_WIDTH{1'b0}}, axis_user_next;

reg s_axis_read_desc_ready_reg = 1'b0, s_axis_read_desc_ready_next;

reg [TAG_WIDTH-1:0] m_axis_read_desc_status_tag_reg = {TAG_WIDTH{1'b0}}, m_axis_read_desc_status_tag_next;
reg [3:0] m_axis_read_desc_status_error_reg = 4'd0, m_axis_read_desc_status_error_next;
reg m_axis_read_desc_status_valid_reg = 1'b0, m_axis_read_desc_status_valid_next;

reg [AXI_ADDR_WIDTH-1:0] m_axi_araddr_reg = {AXI_ADDR_WIDTH{1'b0}}, m_axi_araddr_next;
reg [7:0] m_axi_arlen_reg = 8'd0, m_axi_arlen_next;
reg m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
reg m_axi_rready_reg = 1'b0, m_axi_rready_next;

reg [AXI_DATA_WIDTH-1:0] save_axi_rdata_reg = {AXI_DATA_WIDTH{1'b0}};

wire [AXI_DATA_WIDTH-1:0] shift_axi_rdata = {m_axi_rdata, save_axi_rdata_reg} >> ((AXI_STRB_WIDTH-offset_reg)*AXI_WORD_SIZE);

// internal datapath
reg  [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata_int;
reg  [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep_int;
reg                        m_axis_read_data_tvalid_int;
wire                       m_axis_read_data_tready_int;
reg                        m_axis_read_data_tlast_int;
reg  [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid_int;
reg  [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest_int;
reg  [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser_int;

assign s_axis_read_desc_ready = s_axis_read_desc_ready_reg;

assign m_axis_read_desc_status_tag = m_axis_read_desc_status_tag_reg;
assign m_axis_read_desc_status_error = m_axis_read_desc_status_error_reg;
assign m_axis_read_desc_status_valid = m_axis_read_desc_status_valid_reg;

assign m_axi_arid = {AXI_ID_WIDTH{1'b0}};
assign m_axi_araddr = m_axi_araddr_reg;
assign m_axi_arlen = m_axi_arlen_reg;
assign m_axi_arsize = AXI_BURST_SIZE;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock = 1'b0;
assign m_axi_arcache = 4'b0011;
assign m_axi_arprot = 3'b010;
assign m_axi_arvalid = m_axi_arvalid_reg;
assign m_axi_rready = m_axi_rready_reg;

always @* begin
    axi_state_next = AXI_STATE_IDLE;

    s_axis_read_desc_ready_next = 1'b0;

    m_axi_araddr_next = m_axi_araddr_reg;
    m_axi_arlen_next = m_axi_arlen_reg;
    m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_arready;

    addr_next = addr_reg;
    op_word_count_next = op_word_count_reg;
    tr_word_count_next = tr_word_count_reg;

    axis_cmd_offset_next = axis_cmd_offset_reg;
    axis_cmd_last_cycle_offset_next = axis_cmd_last_cycle_offset_reg;
    axis_cmd_input_cycle_count_next = axis_cmd_input_cycle_count_reg;
    axis_cmd_output_cycle_count_next = axis_cmd_output_cycle_count_reg;
    axis_cmd_bubble_cycle_next = axis_cmd_bubble_cycle_reg;
    axis_cmd_tag_next = axis_cmd_tag_reg;
    axis_cmd_axis_id_next = axis_cmd_axis_id_reg;
    axis_cmd_axis_dest_next = axis_cmd_axis_dest_reg;
    axis_cmd_axis_user_next = axis_cmd_axis_user_reg;
    axis_cmd_valid_next = axis_cmd_valid_reg && !axis_cmd_ready;

    case (axi_state_reg)
        AXI_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            s_axis_read_desc_ready_next = !axis_cmd_valid_reg && enable;

            if (s_axis_read_desc_ready && s_axis_read_desc_valid) begin
                if (ENABLE_UNALIGNED) begin
                    addr_next = s_axis_read_desc_addr;
                    axis_cmd_offset_next = AXI_STRB_WIDTH > 1 ? AXI_STRB_WIDTH - (s_axis_read_desc_addr & OFFSET_MASK) : 0;
                    axis_cmd_bubble_cycle_next = axis_cmd_offset_next > 0;
                    axis_cmd_last_cycle_offset_next = s_axis_read_desc_len & OFFSET_MASK;
                end else begin
                    addr_next = s_axis_read_desc_addr & ADDR_MASK;
                    axis_cmd_offset_next = 0;
                    axis_cmd_bubble_cycle_next = 1'b0;
                    axis_cmd_last_cycle_offset_next = s_axis_read_desc_len & OFFSET_MASK;
                end
                axis_cmd_tag_next = s_axis_read_desc_tag;
                op_word_count_next = s_axis_read_desc_len;

                axis_cmd_axis_id_next = s_axis_read_desc_id;
                axis_cmd_axis_dest_next = s_axis_read_desc_dest;
                axis_cmd_axis_user_next = s_axis_read_desc_user;

                if (ENABLE_UNALIGNED) begin
                    axis_cmd_input_cycle_count_next = (op_word_count_next + (s_axis_read_desc_addr & OFFSET_MASK) - 1) >> AXI_BURST_SIZE;
                end else begin
                    axis_cmd_input_cycle_count_next = (op_word_count_next - 1) >> AXI_BURST_SIZE;
                end
                axis_cmd_output_cycle_count_next = (op_word_count_next - 1) >> AXI_BURST_SIZE;

                axis_cmd_valid_next = 1'b1;

                s_axis_read_desc_ready_next = 1'b0;
                axi_state_next = AXI_STATE_START;
            end else begin
                axi_state_next = AXI_STATE_IDLE;
            end
        end
        AXI_STATE_START: begin
            // start state - initiate new AXI transfer
            if (!m_axi_arvalid) begin
                if (op_word_count_reg <= AXI_MAX_BURST_SIZE - (addr_reg & OFFSET_MASK) || AXI_MAX_BURST_SIZE >= 4096) begin
                    // packet smaller than max burst size
                    if (((addr_reg & 12'hfff) + (op_word_count_reg & 12'hfff)) >> 12 != 0 || op_word_count_reg >> 12 != 0) begin
                        // crosses 4k boundary
                        tr_word_count_next = 13'h1000 - (addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        tr_word_count_next = op_word_count_reg;
                    end
                end else begin
                    // packet larger than max burst size
                    if (((addr_reg & 12'hfff) + AXI_MAX_BURST_SIZE) >> 12 != 0) begin
                        // crosses 4k boundary
                        tr_word_count_next = 13'h1000 - (addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        tr_word_count_next = AXI_MAX_BURST_SIZE - (addr_reg & OFFSET_MASK);
                    end
                end

                m_axi_araddr_next = addr_reg;
                if (ENABLE_UNALIGNED) begin
                    m_axi_arlen_next = (tr_word_count_next + (addr_reg & OFFSET_MASK) - 1) >> AXI_BURST_SIZE;
                end else begin
                    m_axi_arlen_next = (tr_word_count_next - 1) >> AXI_BURST_SIZE;
                end
                m_axi_arvalid_next = 1'b1;

                addr_next = addr_reg + tr_word_count_next;
                op_word_count_next = op_word_count_reg - tr_word_count_next;

                if (op_word_count_next > 0) begin
                    axi_state_next = AXI_STATE_START;
                end else begin
                    s_axis_read_desc_ready_next = !axis_cmd_valid_reg && enable;
                    axi_state_next = AXI_STATE_IDLE;
                end
            end else begin
                axi_state_next = AXI_STATE_START;
            end
        end
    endcase
end

always @* begin
    axis_state_next = AXIS_STATE_IDLE;

    m_axis_read_desc_status_tag_next = m_axis_read_desc_status_tag_reg;
    m_axis_read_desc_status_error_next = m_axis_read_desc_status_error_reg;
    m_axis_read_desc_status_valid_next = 1'b0;

    m_axis_read_data_tdata_int = shift_axi_rdata;
    m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH{1'b1}};
    m_axis_read_data_tlast_int = 1'b0;
    m_axis_read_data_tvalid_int = 1'b0;
    m_axis_read_data_tid_int = axis_id_reg;
    m_axis_read_data_tdest_int = axis_dest_reg;
    m_axis_read_data_tuser_int = axis_user_reg;

    m_axi_rready_next = 1'b0;

    transfer_in_save = 1'b0;
    axis_cmd_ready = 1'b0;

    offset_next = offset_reg;
    last_cycle_offset_next = last_cycle_offset_reg;
    input_cycle_count_next = input_cycle_count_reg;
    output_cycle_count_next = output_cycle_count_reg;
    input_active_next = input_active_reg;
    output_active_next = output_active_reg;
    bubble_cycle_next = bubble_cycle_reg;
    first_cycle_next = first_cycle_reg;
    output_last_cycle_next = output_last_cycle_reg;

    tag_next = tag_reg;
    axis_id_next = axis_id_reg;
    axis_dest_next = axis_dest_reg;
    axis_user_next = axis_user_reg;

    if (m_axi_rready && m_axi_rvalid && (m_axi_rresp == AXI_RESP_SLVERR || m_axi_rresp == AXI_RESP_DECERR)) begin
        rresp_next = m_axi_rresp;
    end else begin
        rresp_next = rresp_reg;
    end

    case (axis_state_reg)
        AXIS_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            m_axi_rready_next = 1'b0;

            // store transfer parameters
            if (ENABLE_UNALIGNED) begin
                offset_next = axis_cmd_offset_reg;
            end else begin
                offset_next = 0;
            end
            last_cycle_offset_next = axis_cmd_last_cycle_offset_reg;
            input_cycle_count_next = axis_cmd_input_cycle_count_reg;
            output_cycle_count_next = axis_cmd_output_cycle_count_reg;
            bubble_cycle_next = axis_cmd_bubble_cycle_reg;
            tag_next = axis_cmd_tag_reg;
            axis_id_next = axis_cmd_axis_id_reg;
            axis_dest_next = axis_cmd_axis_dest_reg;
            axis_user_next = axis_cmd_axis_user_reg;

            output_last_cycle_next = output_cycle_count_next == 0;
            input_active_next = 1'b1;
            output_active_next = 1'b1;
            first_cycle_next = 1'b1;

            if (axis_cmd_valid_reg) begin
                axis_cmd_ready = 1'b1;
                m_axi_rready_next = m_axis_read_data_tready_int;
                axis_state_next = AXIS_STATE_READ;
            end
        end
        AXIS_STATE_READ: begin
            // handle AXI read data
            m_axi_rready_next = m_axis_read_data_tready_int && input_active_reg;

            if ((m_axi_rready && m_axi_rvalid) || !input_active_reg) begin
                // transfer in AXI read data
                transfer_in_save = m_axi_rready && m_axi_rvalid;

                if (ENABLE_UNALIGNED && first_cycle_reg && bubble_cycle_reg) begin
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    bubble_cycle_next = 1'b0;
                    first_cycle_next = 1'b0;

                    m_axi_rready_next = m_axis_read_data_tready_int && input_active_next;
                    axis_state_next = AXIS_STATE_READ;
                end else begin
                    // update counters
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    if (output_active_reg) begin
                        output_cycle_count_next = output_cycle_count_reg - 1;
                        output_active_next = output_cycle_count_reg > 0;
                    end
                    output_last_cycle_next = output_cycle_count_next == 0;
                    bubble_cycle_next = 1'b0;
                    first_cycle_next = 1'b0;

                    // pass through read data
                    m_axis_read_data_tdata_int = shift_axi_rdata;
                    m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH_INT{1'b1}};
                    m_axis_read_data_tvalid_int = 1'b1;

                    if (output_last_cycle_reg) begin
                        // no more data to transfer, finish operation
                        if (last_cycle_offset_reg > 0) begin
                            m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH_INT{1'b1}} >> (AXIS_KEEP_WIDTH_INT - last_cycle_offset_reg);
                        end
                        m_axis_read_data_tlast_int = 1'b1;

                        m_axis_read_desc_status_tag_next = tag_reg;
                        if (rresp_next == AXI_RESP_SLVERR) begin
                            m_axis_read_desc_status_error_next = DMA_ERROR_AXI_RD_SLVERR;
                        end else if (rresp_next == AXI_RESP_DECERR) begin
                            m_axis_read_desc_status_error_next = DMA_ERROR_AXI_RD_DECERR;
                        end else begin
                            m_axis_read_desc_status_error_next = DMA_ERROR_NONE;
                        end
                        m_axis_read_desc_status_valid_next = 1'b1;

                        rresp_next = AXI_RESP_OKAY;

                        m_axi_rready_next = 1'b0;
                        axis_state_next = AXIS_STATE_IDLE;
                    end else begin
                        // more cycles in AXI transfer
                        m_axi_rready_next = m_axis_read_data_tready_int && input_active_next;
                        axis_state_next = AXIS_STATE_READ;
                    end
                end
            end else begin
                axis_state_next = AXIS_STATE_READ;
            end
        end
    endcase
end

always @(posedge clk) begin
    axi_state_reg <= axi_state_next;
    axis_state_reg <= axis_state_next;

    s_axis_read_desc_ready_reg <= s_axis_read_desc_ready_next;

    m_axis_read_desc_status_tag_reg <= m_axis_read_desc_status_tag_next;
    m_axis_read_desc_status_error_reg <= m_axis_read_desc_status_error_next;
    m_axis_read_desc_status_valid_reg <= m_axis_read_desc_status_valid_next;

    m_axi_araddr_reg <= m_axi_araddr_next;
    m_axi_arlen_reg <= m_axi_arlen_next;
    m_axi_arvalid_reg <= m_axi_arvalid_next;
    m_axi_rready_reg <= m_axi_rready_next;

    addr_reg <= addr_next;
    op_word_count_reg <= op_word_count_next;
    tr_word_count_reg <= tr_word_count_next;

    axis_cmd_offset_reg <= axis_cmd_offset_next;
    axis_cmd_last_cycle_offset_reg <= axis_cmd_last_cycle_offset_next;
    axis_cmd_input_cycle_count_reg <= axis_cmd_input_cycle_count_next;
    axis_cmd_output_cycle_count_reg <= axis_cmd_output_cycle_count_next;
    axis_cmd_bubble_cycle_reg <= axis_cmd_bubble_cycle_next;
    axis_cmd_tag_reg <= axis_cmd_tag_next;
    axis_cmd_axis_id_reg <= axis_cmd_axis_id_next;
    axis_cmd_axis_dest_reg <= axis_cmd_axis_dest_next;
    axis_cmd_axis_user_reg <= axis_cmd_axis_user_next;
    axis_cmd_valid_reg <= axis_cmd_valid_next;

    offset_reg <= offset_next;
    last_cycle_offset_reg <= last_cycle_offset_next;
    input_cycle_count_reg <= input_cycle_count_next;
    output_cycle_count_reg <= output_cycle_count_next;
    input_active_reg <= input_active_next;
    output_active_reg <= output_active_next;
    bubble_cycle_reg <= bubble_cycle_next;
    first_cycle_reg <= first_cycle_next;
    output_last_cycle_reg <= output_last_cycle_next;
    rresp_reg <= rresp_next;

    tag_reg <= tag_next;
    axis_id_reg <= axis_id_next;
    axis_dest_reg <= axis_dest_next;
    axis_user_reg <= axis_user_next;

    if (transfer_in_save) begin
        save_axi_rdata_reg <= m_axi_rdata;
    end

    if (rst) begin
        axi_state_reg <= AXI_STATE_IDLE;
        axis_state_reg <= AXIS_STATE_IDLE;

        axis_cmd_valid_reg <= 1'b0;

        s_axis_read_desc_ready_reg <= 1'b0;

        m_axis_read_desc_status_valid_reg <= 1'b0;
        m_axi_arvalid_reg <= 1'b0;
        m_axi_rready_reg <= 1'b0;

        rresp_reg <= AXI_RESP_OKAY;
    end
end

// output datapath logic
reg [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata_reg  = {AXIS_DATA_WIDTH{1'b0}};
reg [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep_reg  = {AXIS_KEEP_WIDTH{1'b0}};
reg                       m_axis_read_data_tvalid_reg = 1'b0;
reg                       m_axis_read_data_tlast_reg  = 1'b0;
reg [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid_reg    = {AXIS_ID_WIDTH{1'b0}};
reg [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest_reg  = {AXIS_DEST_WIDTH{1'b0}};
reg [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser_reg  = {AXIS_USER_WIDTH{1'b0}};

reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
reg out_fifo_half_full_reg = 1'b0;

wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [AXIS_DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [AXIS_KEEP_WIDTH-1:0] out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg                       out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [AXIS_ID_WIDTH-1:0]   out_fifo_tid[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [AXIS_DEST_WIDTH-1:0] out_fifo_tdest[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [AXIS_USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

assign m_axis_read_data_tready_int = !out_fifo_half_full_reg;

assign m_axis_read_data_tdata  = m_axis_read_data_tdata_reg;
assign m_axis_read_data_tkeep  = AXIS_KEEP_ENABLE ? m_axis_read_data_tkeep_reg : {AXIS_KEEP_WIDTH{1'b1}};
assign m_axis_read_data_tvalid = m_axis_read_data_tvalid_reg;
assign m_axis_read_data_tlast  = AXIS_LAST_ENABLE ? m_axis_read_data_tlast_reg : 1'b1;
assign m_axis_read_data_tid    = AXIS_ID_ENABLE   ? m_axis_read_data_tid_reg   : {AXIS_ID_WIDTH{1'b0}};
assign m_axis_read_data_tdest  = AXIS_DEST_ENABLE ? m_axis_read_data_tdest_reg : {AXIS_DEST_WIDTH{1'b0}};
assign m_axis_read_data_tuser  = AXIS_USER_ENABLE ? m_axis_read_data_tuser_reg : {AXIS_USER_WIDTH{1'b0}};

always @(posedge clk) begin
    m_axis_read_data_tvalid_reg <= m_axis_read_data_tvalid_reg && !m_axis_read_data_tready;

    out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

    if (!out_fifo_full && m_axis_read_data_tvalid_int) begin
        out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tdata_int;
        out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tkeep_int;
        out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tlast_int;
        out_fifo_tid[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tid_int;
        out_fifo_tdest[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tdest_int;
        out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_read_data_tuser_int;
        out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
    end

    if (!out_fifo_empty && (!m_axis_read_data_tvalid_reg || m_axis_read_data_tready)) begin
        m_axis_read_data_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_read_data_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_read_data_tvalid_reg <= 1'b1;
        m_axis_read_data_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_read_data_tid_reg <= out_fifo_tid[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_read_data_tdest_reg <= out_fifo_tdest[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_read_data_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
    end

    if (rst) begin
        out_fifo_wr_ptr_reg <= 0;
        out_fifo_rd_ptr_reg <= 0;
        m_axis_read_data_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall


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
module matrix_staging_to_sram (
 input wire clk, rst_n, pair_valid,
 output wire [3:0] rd_index,
 input wire [7:0] a_rd_data, b_rd_data,
 output wire busy,
 output reg done,
 input wire debug_sel,
 input wire [1:0] debug_bank, debug_addr,
 output wire [7:0] debug_data,
 output wire a_wr_en, b_wr_en,
 output wire [1:0] a_wr_bank,a_wr_addr,b_wr_bank,b_wr_addr,
 output wire signed [7:0] a_wr_data,b_wr_data
);
 localparam ST_IDLE=2'd0, ST_A=2'd1, ST_B=2'd2;
 reg [1:0] state;
 reg [3:0] index;
 reg pair_d;
 reg [7:0] a_sram [0:15];
 reg [7:0] b_sram [0:15];
 integer i;
 assign a_wr_en=(state==ST_A);
 assign b_wr_en=(state==ST_B);
 assign a_wr_bank=index[3:2];
 assign a_wr_addr=index[1:0];
 assign b_wr_bank=index[1:0];
 assign b_wr_addr=index[3:2];
 assign a_wr_data=a_rd_data;
 assign b_wr_data=b_rd_data;
 assign rd_index=index;
 assign busy=(state!=ST_IDLE);
 assign debug_data=debug_sel ? b_sram[{debug_bank,debug_addr}] : a_sram[{debug_bank,debug_addr}];
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   state<=ST_IDLE; index<=0; pair_d<=0; done<=0;
   for (i=0;i<16;i=i+1) begin a_sram[i]<=0; b_sram[i]<=0; end
  end else begin
   pair_d<=pair_valid;
   done<=0;
   case(state)
    ST_IDLE: if (pair_valid && !pair_d) begin index<=0; state<=ST_A; end
    ST_A: begin
     a_sram[index]<=a_rd_data;
     if (index==15) begin index<=0; state<=ST_B; end
     else index<=index+1'b1;
    end
    ST_B: begin
     b_sram[{index[1:0],index[3:2]}]<=b_rd_data;
     if (index==15) begin index<=0; state<=ST_IDLE; done<=1; end
     else index<=index+1'b1;
    end
    default: state<=ST_IDLE;
   endcase
  end
 end
endmodule

`timescale 1ns/1ps
module matrix_dma_job_manager (
 input wire clk,rst_n,start,
 input wire [31:0] a_base_addr,b_base_addr,
 output wire dma_start,
 output wire [31:0] dma_a_addr,dma_b_addr,
 input wire dma_busy,dma_done,dma_error,
 input wire sram_busy,sram_done,
 output wire busy,
 output reg done,error
);
 localparam IDLE=2'd0, START_DMA=2'd1, WAIT_DMA=2'd2, WAIT_SRAM=2'd3;
 reg [1:0] state;
 reg [31:0] a_addr_reg,b_addr_reg;
 assign busy=(state!=IDLE);
 assign dma_start=(state==START_DMA);
 assign dma_a_addr=a_addr_reg;
 assign dma_b_addr=b_addr_reg;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE; a_addr_reg<=0; b_addr_reg<=0; done<=0; error<=0;
  end else begin
   done<=0; error<=0;
   case(state)
    IDLE: if(start) begin
     a_addr_reg<=a_base_addr; b_addr_reg<=b_base_addr; state<=START_DMA;
    end
    START_DMA: state<=WAIT_DMA;
    WAIT_DMA: begin
     if(dma_error) begin error<=1; state<=IDLE; end
     else if(dma_done) state<=WAIT_SRAM;
    end
    WAIT_SRAM: if(sram_done) begin done<=1; state<=IDLE; end
    default: state<=IDLE;
   endcase
  end
 end
endmodule

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
module matrix_dma_compute_top (
 input wire clk,rst_n,start,
 input wire [31:0] a_base_addr,b_base_addr,
 output wire busy,done,error,
 input wire [3:0] c_rd_addr,
 output wire signed [31:0] c_rd_data,
 output wire [31:0] desc_addr,
 output wire [19:0] desc_len,
 output wire [7:0] desc_tag,
 output wire desc_valid,
 input wire desc_ready,
 output wire [31:0] tdata,
 output wire [3:0] tkeep,
 output wire tvalid,tlast,
 input wire tready,
 input wire [7:0] status_tag,
 input wire [3:0] status_error,
 input wire status_valid,
 output wire [31:0] araddr,
 output wire [7:0] arlen,
 output wire [2:0] arsize,
 output wire [1:0] arburst,
 output wire arvalid,
 input wire arready,
 input wire [31:0] rdata,
 input wire [1:0] rresp,
 input wire rvalid,rlast,
 output wire rready
);
 wire load_start,load_busy,load_done,load_error;
 wire dma_start,dma_busy,dma_done,dma_error;
 wire [31:0] dma_a_addr,dma_b_addr;
 wire staging_start,matrix_sel,operand_done,operand_error,pair_valid,cmd_ready,staging_busy;
 wire [3:0] staging_rd_index;
 wire [7:0] staging_a_data,staging_b_data;
 wire sram_busy,sram_done;
 wire a_wr_en,b_wr_en;
 wire [1:0] a_wr_bank,a_wr_addr,b_wr_bank,b_wr_addr;
 wire signed [7:0] a_wr_data,b_wr_data;
 wire compute_busy,compute_done,compute_start;
 reg [2:0] state;
 reg done_reg,error_reg;
 localparam IDLE=0, LOAD=1, COMPUTE_START=2, COMPUTE_WAIT=3, FINISH=4;
 reg [31:0] a_addr_reg,b_addr_reg;
 assign busy=(state!=IDLE);
 assign done=done_reg;
 assign error=error_reg;
 assign load_start=(state==LOAD) && !load_busy && !load_done && !load_launched;
 reg load_launched;
 assign compute_start=(state==COMPUTE_START);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;done_reg<=0;error_reg<=0;load_launched<=0;
   a_addr_reg<=0;b_addr_reg<=0;
  end else begin
   done_reg<=0;error_reg<=0;
   case(state)
    IDLE: if(start) begin
      a_addr_reg<=a_base_addr;b_addr_reg<=b_base_addr;
      load_launched<=0;state<=LOAD;
    end
    LOAD: begin
      if(load_start) load_launched<=1;
      if(load_error) begin error_reg<=1;state<=IDLE;end
      else if(load_done) state<=COMPUTE_START;
    end
    COMPUTE_START: state<=COMPUTE_WAIT;
    COMPUTE_WAIT: if(compute_done) state<=FINISH;
    FINISH: begin done_reg<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
 matrix_dma_job_manager manager (
  .clk(clk),.rst_n(rst_n),.start(load_start),
  .a_base_addr(a_addr_reg),.b_base_addr(b_addr_reg),
  .dma_start(dma_start),.dma_a_addr(dma_a_addr),.dma_b_addr(dma_b_addr),
  .dma_busy(dma_busy),.dma_done(dma_done),.dma_error(dma_error),
  .sram_busy(sram_busy),.sram_done(sram_done),
  .busy(load_busy),.done(load_done),.error(load_error)
 );
 matrix_dma_controller controller (
  .clk(clk),.rst_n(rst_n),.start(dma_start),
  .a_base_addr(dma_a_addr),.b_base_addr(dma_b_addr),
  .desc_addr(desc_addr),.desc_len(desc_len),.desc_tag(desc_tag),
  .desc_valid(desc_valid),.desc_ready(desc_ready),
  .staging_start(staging_start),.matrix_sel(matrix_sel),
  .operand_done(operand_done),.operand_error(operand_error),
  .busy(dma_busy),.done(dma_done),.error(dma_error)
 );
 matrix_dma_staging_v2 staging (
  .clk(clk),.rst_n(rst_n),.start(staging_start),.matrix_sel(matrix_sel),
  .cmd_ready(cmd_ready),.busy(staging_busy),
  .s_axis_tdata(tdata),.s_axis_tkeep(tkeep),
  .s_axis_tvalid(tvalid),.s_axis_tready(tready),.s_axis_tlast(tlast),
  .dma_status_valid(status_valid),.dma_status_tag(status_tag),
  .dma_status_error(status_error),.operand_done(operand_done),
  .operand_error(operand_error),.pair_valid(pair_valid),
  .rd_index(staging_rd_index),.a_rd_data(staging_a_data),.b_rd_data(staging_b_data)
 );
 matrix_staging_to_sram mapper (
  .clk(clk),.rst_n(rst_n),.pair_valid(pair_valid),
  .rd_index(staging_rd_index),.a_rd_data(staging_a_data),.b_rd_data(staging_b_data),
  .busy(sram_busy),.done(sram_done),
  .debug_sel(1'b0),.debug_bank(2'b00),.debug_addr(2'b00),.debug_data(),
  .a_wr_en(a_wr_en),.b_wr_en(b_wr_en),
  .a_wr_bank(a_wr_bank),.a_wr_addr(a_wr_addr),
  .b_wr_bank(b_wr_bank),.b_wr_addr(b_wr_addr),
  .a_wr_data(a_wr_data),.b_wr_data(b_wr_data)
 );
 matrix_accelerator_v4_top compute (
  .clk(clk),.rst_n(rst_n),.start(compute_start),
  .busy(compute_busy),.done(compute_done),
  .a_wr_en(a_wr_en),.a_wr_bank(a_wr_bank),.a_wr_addr(a_wr_addr),.a_wr_data(a_wr_data),
  .b_wr_en(b_wr_en),.b_wr_bank(b_wr_bank),.b_wr_addr(b_wr_addr),.b_wr_data(b_wr_data),
  .c_rd_addr(c_rd_addr),.c_rd_data(c_rd_data)
 );
 axi_dma_rd #(
  .AXI_DATA_WIDTH(32),.AXI_ADDR_WIDTH(32),.AXI_ID_WIDTH(8),
  .AXI_MAX_BURST_LEN(256),.AXIS_DATA_WIDTH(32),
  .AXIS_KEEP_ENABLE(1),.AXIS_KEEP_WIDTH(4),.AXIS_LAST_ENABLE(1),
  .AXIS_ID_ENABLE(0),.AXIS_ID_WIDTH(8),
  .AXIS_DEST_ENABLE(0),.AXIS_DEST_WIDTH(8),
  .AXIS_USER_ENABLE(0),.AXIS_USER_WIDTH(1),
  .LEN_WIDTH(20),.TAG_WIDTH(8),.ENABLE_SG(0),.ENABLE_UNALIGNED(0)
 ) dma (
  .clk(clk),.rst(~rst_n),
  .s_axis_read_desc_addr(desc_addr),.s_axis_read_desc_len(desc_len),
  .s_axis_read_desc_tag(desc_tag),.s_axis_read_desc_id(8'd0),
  .s_axis_read_desc_dest(8'd0),.s_axis_read_desc_user(1'b0),
  .s_axis_read_desc_valid(desc_valid),.s_axis_read_desc_ready(desc_ready),
  .m_axis_read_desc_status_tag(status_tag),
  .m_axis_read_desc_status_error(status_error),
  .m_axis_read_desc_status_valid(status_valid),
  .m_axis_read_data_tdata(tdata),.m_axis_read_data_tkeep(tkeep),
  .m_axis_read_data_tvalid(tvalid),.m_axis_read_data_tready(tready),
  .m_axis_read_data_tlast(tlast),
  .m_axis_read_data_tid(),.m_axis_read_data_tdest(),.m_axis_read_data_tuser(),
  .m_axi_arid(),.m_axi_araddr(araddr),.m_axi_arlen(arlen),
  .m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arlock(),
  .m_axi_arcache(),.m_axi_arprot(),.m_axi_arvalid(arvalid),
  .m_axi_arready(arready),.m_axi_rid(8'd0),.m_axi_rdata(rdata),
  .m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),
  .m_axi_rready(rready),.enable(1'b1)
 );
endmodule
