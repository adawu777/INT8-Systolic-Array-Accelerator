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
