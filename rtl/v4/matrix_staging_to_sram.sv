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
