`timescale 1ns/1ps
module tb_step9h;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 reg start=0;
 reg [31:0] a_base_addr=0,b_base_addr=0;
 wire busy,done,error;
 reg [3:0] c_rd_addr=0;
 wire signed [31:0] c_rd_data;
 wire [31:0] desc_addr,araddr,tdata;
 wire [19:0] desc_len;
 wire [7:0] desc_tag,arlen,status_tag;
 wire desc_valid,desc_ready,arvalid,arready,rvalid,rready,rlast;
 wire [3:0] tkeep,status_error;
 wire tvalid,tready,tlast,status_valid;
 wire [2:0] arsize;
 wire [1:0] arburst,rresp;
 wire [31:0] rdata;
 integer desc_count=0,ar_count=0,r_count=0,stream_count=0,status_count=0;
 integer dma_done_count=0,sram_done_count=0,job_done_count=0;
 integer a_write_count=0,b_write_count=0;
 matrix_dma_compute_top dut(
  .clk(clk),.rst_n(rst_n),.start(start),
  .a_base_addr(a_base_addr),.b_base_addr(b_base_addr),
  .busy(busy),.done(done),.error(error),
  .c_rd_addr(c_rd_addr),.c_rd_data(c_rd_data),
  .desc_addr(desc_addr),.desc_len(desc_len),.desc_tag(desc_tag),
  .desc_valid(desc_valid),.desc_ready(desc_ready),
  .tdata(tdata),.tkeep(tkeep),.tvalid(tvalid),.tlast(tlast),.tready(tready),
  .status_tag(status_tag),.status_error(status_error),.status_valid(status_valid),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
  .arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rlast(rlast),.rready(rready)
 );
 // Simple AXI4 memory model: four 16-byte matrices.
 reg mem_active=0;
 reg [31:0] mem_addr=0;
 reg [8:0] mem_beat=0,mem_total=0;
 reg inject_error=0;
 integer cycle_count=0;
 integer ar_stall_cycles=0,r_stall_cycles=0,busy_start_count=0;
 always @(posedge clk or negedge rst_n)
  if (!rst_n) cycle_count<=0;
  else cycle_count<=cycle_count+1;
 // Deterministic AXI backpressure. R beat/address stay stable until handshake.
 assign arready=!mem_active && ((cycle_count % 5)==0);
 assign rvalid=mem_active && ((cycle_count % 4)!=0);
 assign rresp=(inject_error && mem_active) ? 2'b10 : 2'b00;
 assign rlast=mem_active && (mem_beat==mem_total-1);
 wire [31:0] current_addr=mem_addr+({23'd0,mem_beat}<<2);
 function [7:0] memory_byte;
  input [31:0] addr;
  reg [31:0] offset;
  begin
   if(addr>=32'h1000 && addr<32'h1010) begin offset=addr-32'h1000; memory_byte=offset+1; end
   else if(addr>=32'h2000 && addr<32'h2010) begin offset=addr-32'h2000; memory_byte=offset+21; end
   else if(addr>=32'h3000 && addr<32'h3010) begin offset=addr-32'h3000; memory_byte=offset+41; end
   else if(addr>=32'h4000 && addr<32'h4010) begin offset=addr-32'h4000; memory_byte=offset+61; end
   else if(addr>=32'h5000 && addr<32'h5010) begin offset=addr-32'h5000; memory_byte=offset+81; end
   else if(addr>=32'h6000 && addr<32'h6010) begin offset=addr-32'h6000; memory_byte=offset+101; end
   else memory_byte=8'hEE;
  end
 endfunction
 assign rdata={memory_byte(current_addr+3),memory_byte(current_addr+2),
               memory_byte(current_addr+1),memory_byte(current_addr)};
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin mem_active<=0;mem_addr<=0;mem_beat<=0;mem_total<=0; end
  else if(arvalid && arready) begin
   if(arsize!==3'd2 || arburst!==2'b01)
    $fatal(1,"Unexpected AXI AR size/burst");
   mem_active<=1; mem_addr<=araddr; mem_beat<=0; mem_total<={1'b0,arlen}+9'd1;
  end else if(rvalid && rready) begin
   if(rlast) begin mem_active<=0;mem_beat<=0; end
   else mem_beat<=mem_beat+1'b1;
  end
 end
 always @(posedge clk) if(rst_n) begin
  if(arvalid && !arready) ar_stall_cycles=ar_stall_cycles+1;
  if(mem_active && !rvalid) r_stall_cycles=r_stall_cycles+1;
  if(desc_valid && desc_ready) begin
   desc_count=desc_count+1;
   $display("DMA DESC addr=%h len=%0d tag=%h",desc_addr,desc_len,desc_tag);
  end
  if(arvalid && arready) begin
   ar_count=ar_count+1;
   $display("AXI AR addr=%h beats=%0d",araddr,arlen+1);
  end
  if(rvalid && rready) r_count=r_count+1;
  if(tvalid && tready) stream_count=stream_count+1;
  if(status_valid) begin
   status_count=status_count+1;
   $display("DMA STATUS tag=%h error=%0d",status_tag,status_error);
  end
  if(dut.dma_done) dma_done_count=dma_done_count+1;
  if(dut.sram_done) sram_done_count=sram_done_count+1;
  if(done) job_done_count=job_done_count+1;
  if(dut.mapper.state==2'd1) a_write_count=a_write_count+1;
  if(dut.mapper.state==2'd2) b_write_count=b_write_count+1;
  if(error || dut.dma_error || dut.operand_error) $fatal(1,"Unexpected DMA/staging/job error");
  if(done && (dut.sram_busy || dut.dma_busy || dut.compute_busy)) $fatal(1,"Job completed before subsystems idle");
 end


 task start_job;
  input [31:0] a_addr,b_addr;
  begin
   @(negedge clk);
   if(busy) $fatal(1,"Start attempted while busy");
   a_base_addr=a_addr;b_base_addr=b_addr;start=1;
   @(negedge clk);start=0;
  end
 endtask
 task wait_job;
  input integer expected;
  integer timeout;
  begin
   timeout=0;
   while(job_done_count<expected && timeout<350) begin
    @(negedge clk);timeout=timeout+1;
   end
   if(job_done_count!=expected) $fatal(1,"Job timeout expected=%0d got=%0d",expected,job_done_count);
   if(busy) $fatal(1,"Job busy after completion");
  end
 endtask
 task check_result;
  input integer a_first,b_first;
  integer row,col,k,expected,aval,bval;
  begin
   for(row=0;row<4;row=row+1) begin
    for(col=0;col<4;col=col+1) begin
     expected=0;
     for(k=0;k<4;k=k+1) begin
      aval=a_first+row*4+k;
      bval=b_first+k*4+col;
      expected=expected+aval*bval;
     end
     @(negedge clk);c_rd_addr=row*4+col;
     @(posedge clk);#1;
     if(c_rd_data !== expected)
      $fatal(1,"C[%0d][%0d] mismatch got=%0d expected=%0d",row,col,c_rd_data,expected);
    end
   end
  end
 endtask
 initial begin
  repeat(5) @(negedge clk);rst_n=1;
  repeat(2) @(negedge clk);
  $display("TEST 1: Backpressured DMA A0/B0 -> Compute -> C SRAM");
  start_job(32'h1000,32'h2000);
  wait_job(1);
  check_result(1,21);
  $display("TEST 1 PASSED");
  $display("TEST 2: Busy start ignored + second job without reset");
  start_job(32'h3000,32'h4000);
  // Issue a spurious start while the second job is busy.
  // Addresses point at a different valid matrix and must be ignored.
  @(negedge clk);
  if(!busy) $fatal(1,"Expected busy during second job");
  a_base_addr=32'h5000;b_base_addr=32'h6000;start=1;
  busy_start_count=busy_start_count+1;
  @(negedge clk);start=0;
  wait_job(2);
  check_result(41,61);
  $display("TEST 2 PASSED");
  $display("TEST 3: Third matrix job without reset");
  start_job(32'h5000,32'h6000);
  wait_job(3);
  check_result(81,101);
  $display("TEST 3 PASSED");
  if(ar_stall_cycles==0 || r_stall_cycles==0 || busy_start_count!=1)
   $fatal(1,"Backpressure/busy-start coverage missing: AR=%0d R=%0d busy_start=%0d",ar_stall_cycles,r_stall_cycles,busy_start_count);
  if(desc_count!=6 || ar_count!=6 || r_count!=24 || stream_count!=24 || status_count!=6 ||
     dma_done_count!=3 || sram_done_count!=3 || job_done_count!=3 ||
     a_write_count!=48 || b_write_count!=48)
   $fatal(1,"Integration counter mismatch");
  $display("ALL STEP 9H-A BACKPRESSURE REGRESSION TESTS PASSED");
  $display("Descriptors=%0d AXI_AR=%0d AXI_R=%0d Stream=%0d Status=%0d",desc_count,ar_count,r_count,stream_count,status_count);
  $display("DMA_done=%0d SRAM_done=%0d Jobs=%0d A_writes=%0d B_writes=%0d",dma_done_count,sram_done_count,job_done_count,a_write_count,b_write_count);
  $display("AR_stall_cycles=%0d R_stall_cycles=%0d Busy_starts_ignored=%0d",ar_stall_cycles,r_stall_cycles,busy_start_count);
  $finish;
 end
 initial begin #150000; $fatal(1,"GLOBAL TIMEOUT"); end
endmodule
