`timescale 1ns/1ps
module tb_step9h_b;
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
 integer a_ok_status_count=0,b_ok_status_count=0;
 integer a_err_status_count=0,b_err_status_count=0;
 reg [3:0] last_a_error=0,last_b_error=0;
 integer stream_last_count=0;

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
 reg [31:0] error_address=0;
 reg [1:0] injected_rresp=0;
 reg expect_error=0;
 integer cycle_count=0;
 integer ar_stall_cycles=0,r_stall_cycles=0,busy_start_count=0;
 always @(posedge clk or negedge rst_n)
  if (!rst_n) cycle_count<=0;
  else cycle_count<=cycle_count+1;
 // Deterministic AXI backpressure. R beat/address stay stable until handshake.
 assign arready=!mem_active && ((cycle_count % 5)==0);
 // Registered AXI R channel. VALID and payload remain stable during stalls.
 reg rvalid_reg=0,rlast_reg=0;
 reg [1:0] rresp_reg=0;
 reg [31:0] rdata_reg=0;
 assign rvalid=rvalid_reg;
 assign rlast=rlast_reg;
 assign rresp=rresp_reg;
 assign rdata=rdata_reg;
 wire r_fire=rvalid && rready;
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
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   mem_active<=0;mem_addr<=0;mem_beat<=0;mem_total<=0;
   rvalid_reg<=0;rlast_reg<=0;rresp_reg<=0;rdata_reg<=0;
  end else if(arvalid && arready) begin
   if(mem_active || arsize!==3'd2 || arburst!==2'b01)
    $fatal(1,"Unexpected AXI AR size/burst or overlapping burst");
   mem_active<=1;mem_addr<=araddr;mem_beat<=0;
   mem_total<={1'b0,arlen}+9'd1;
   rvalid_reg<=0;
  end else if(mem_active) begin
   if(r_fire) begin
    rvalid_reg<=0;
    if(rlast_reg) begin mem_active<=0;mem_beat<=0; end
    else mem_beat<=mem_beat+1'b1;
   end else if(!rvalid_reg && ((cycle_count % 4)!=0)) begin
    rvalid_reg<=1;
    rdata_reg<={memory_byte(current_addr+3),memory_byte(current_addr+2),
                memory_byte(current_addr+1),memory_byte(current_addr)};
    rlast_reg<=(mem_beat==mem_total-1);
    rresp_reg<=(mem_addr==error_address && mem_beat==mem_total-1)
                ? injected_rresp : 2'b00;
   end
  end
 end
 // AXI stability assertion: if stalled, VALID and payload must persist.
 reg prev_stalled=0;
 reg [31:0] prev_data=0;
 reg [1:0] prev_resp=0;
 reg prev_last=0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) prev_stalled<=0;
  else begin
   if(prev_stalled && (!rvalid || rdata!==prev_data ||
                       rresp!==prev_resp || rlast!==prev_last))
    $fatal(1,"AXI R payload changed while stalled");
   prev_stalled<=rvalid && !rready;
   prev_data<=rdata;prev_resp<=rresp;prev_last<=rlast;
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
  if(tvalid && tready) begin
   stream_count=stream_count+1;
   if(tlast) stream_last_count=stream_last_count+1;
   $display("STREAM t=%0t data=%h keep=%h last=%b",$time,tdata,tkeep,tlast);
  end
  if(status_valid) begin
   status_count=status_count+1;
   if(status_tag==8'hA1) begin
    last_a_error=status_error;
    if(status_error==0) a_ok_status_count=a_ok_status_count+1;
    else a_err_status_count=a_err_status_count+1;
   end else if(status_tag==8'hB1) begin
    last_b_error=status_error;
    if(status_error==0) b_ok_status_count=b_ok_status_count+1;
    else b_err_status_count=b_err_status_count+1;
   end else $fatal(1,"Unexpected DMA status tag=%h",status_tag);
   $display("DMA STATUS tag=%h error=%0d",status_tag,status_error);
  end
  if(dut.dma_done) dma_done_count=dma_done_count+1;
  if(dut.sram_done) sram_done_count=sram_done_count+1;
  if(done) job_done_count=job_done_count+1;
  if(dut.mapper.state==2'd1) a_write_count=a_write_count+1;
  if(dut.mapper.state==2'd2) b_write_count=b_write_count+1;
  if(dut.operand_error || dut.dma_error || dut.load_error || error)
   $display("ERROR TRACE t=%0t operand=%b dma=%b load=%b top=%b beat_count=%0d frame_error=%b",$time,dut.operand_error,dut.dma_error,dut.load_error,error,dut.staging.beat_count,dut.staging.frame_error);
  if(!expect_error && (error || dut.dma_error || dut.operand_error)) $fatal(1,"Unexpected DMA/staging/job error");
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
 integer error_count=0;
 integer d0=0,s0=0,a0=0;
 integer successful_jobs=0;
 always @(posedge clk) if(rst_n) begin
   if(error) error_count=error_count+1;
   if(done) successful_jobs=successful_jobs+1;
 end
 task wait_error;
  input integer target;
  integer timeout;
  begin
   timeout=0;
   while(error_count<target && timeout<400) begin
    @(negedge clk);timeout=timeout+1;
   end
   if(error_count!=target) $fatal(1,"Expected error pulse count=%0d actual=%0d",target,error_count);
   @(negedge clk);
   if(busy) $fatal(1,"DUT busy after job error");
   if(dut.compute_busy) $fatal(1,"Compute activated after DMA error");
  end
 endtask
 task reset_dut;
  begin
   @(negedge clk);rst_n=0;start=0;
   repeat(5) @(negedge clk);
   rst_n=1;
   repeat(3) @(negedge clk);
   if(busy || done || error || dut.dma_busy || dut.sram_busy || dut.compute_busy)
    $fatal(1,"Subsystem not idle after reset");
  end
 endtask
 task successful_job;
  input [31:0] aa,bb;
  input integer a_first,b_first;
  integer target,timeout;
  begin
   target=successful_jobs+1;
   start_job(aa,bb);
   timeout=0;
   while(successful_jobs<target && timeout<500) begin
    @(negedge clk);timeout=timeout+1;
   end
   if(successful_jobs!=target) $fatal(1,"Recovery job timeout");
   if(busy || error) $fatal(1,"Bad job status after recovery");
   check_result(a_first,b_first);
  end
 endtask
 initial begin
  repeat(5) @(negedge clk);rst_n=1;
  repeat(2) @(negedge clk);
  $display("TEST 1: A DMA SLVERR prevents compute");
  expect_error=1;error_address=32'h1000;injected_rresp=2'b10;
  start_job(32'h1000,32'h2000);
  wait_error(1);
  if(successful_jobs!=0) $fatal(1,"Unexpected successful job after A SLVERR");
  if(a_err_status_count!=1 || last_a_error==0 || desc_count!=1 || status_count!=1)
   $fatal(1,"TEST 1 coverage failure: A SLVERR status not confirmed");
  $display("TEST 1 PASSED");

  $display("TEST 2: B DMA DECERR prevents compute");
  d0=desc_count;s0=status_count;a0=ar_count;
  error_address=32'h4000;injected_rresp=2'b11;
  start_job(32'h3000,32'h4000);
  wait_error(2);
  if(successful_jobs!=0) $fatal(1,"Unexpected successful job after B DECERR");
  if(desc_count-d0!=2 || ar_count-a0!=2 || status_count-s0!=2 ||
     a_ok_status_count<1 || b_err_status_count!=1 || last_b_error==0)
   $fatal(1,"TEST 2 coverage failure: B DECERR not reached; desc_delta=%0d ar_delta=%0d status_delta=%0d B_errors=%0d",desc_count-d0,ar_count-a0,status_count-s0,b_err_status_count);
  $display("TEST 2 PASSED");

  $display("TEST 3: Recovery job after DMA errors without reset");
  expect_error=0;error_address=0;injected_rresp=0;
  successful_job(32'h1000,32'h2000,1,21);
  $display("TEST 3 PASSED");

  $display("TEST 4: Reset during active DMA transfer");
  start_job(32'h3000,32'h4000);
  wait(rvalid && rready);
  reset_dut();
  successful_job(32'h3000,32'h4000,41,61);
  $display("TEST 4 PASSED");

  $display("TEST 5: Reset during compute");
  start_job(32'h5000,32'h6000);
  wait(dut.compute_busy);
  reset_dut();
  successful_job(32'h5000,32'h6000,81,101);
  $display("TEST 5 PASSED");

  if(error_count!=2 || successful_jobs!=3)
    $fatal(1,"Unexpected error/success counts errors=%0d successes=%0d",error_count,successful_jobs);
  $display("ALL STEP 9H-B ERROR/RESET RECOVERY TESTS PASSED");
  $display("Errors=%0d RecoveryJobs=%0d",error_count,successful_jobs);
  $display("Descriptors=%0d AXI_AR=%0d AXI_R=%0d Stream=%0d TLAST=%0d Status=%0d",desc_count,ar_count,r_count,stream_count,stream_last_count,status_count);
  $finish;
 end
 initial begin #200000; $fatal(1,"GLOBAL TIMEOUT"); end
endmodule
