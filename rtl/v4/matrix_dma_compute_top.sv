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
