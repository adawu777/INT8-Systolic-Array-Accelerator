`timescale 1ns/1ps
module tb_step9h_c;
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
 // AXI4 memory model with deterministic pseudo-random stalls.
 reg mem_active=0;
 reg [31:0] mem_addr=0;
 reg [8:0] mem_beat=0,mem_total=0;
 reg [31:0] error_address=0;
 reg [1:0] injected_rresp=0;
 reg expect_error=0;
 integer cycle_count=0;
 reg [31:0] prng=32'hC0FFEE21;
 integer seed=0;
 integer jobs_verified=0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) prng<=32'hC0FFEE21;
  else prng<={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
 end
 integer ar_stall_cycles=0,r_stall_cycles=0,busy_start_count=0;
 always @(posedge clk or negedge rst_n)
  if (!rst_n) cycle_count<=0;
  else cycle_count<=cycle_count+1;
 // Deterministic AXI backpressure. R beat/address stay stable until handshake.
 assign arready=!mem_active && prng[3] && prng[7];
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
   end else if(!rvalid_reg && (prng[5] && prng[9])) begin
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
 // AXI-Stream stability assertion (sampled on rising edges).
 reg stream_prev_stall=0;
 reg [31:0] stream_prev_data=0;
 reg [3:0] stream_prev_keep=0;
 reg stream_prev_last=0;
 reg desc_prev_stall=0;
 reg [31:0] desc_prev_addr=0;
 reg [19:0] desc_prev_len=0;
 reg [7:0] desc_prev_tag=0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   stream_prev_stall<=0;
   desc_prev_stall<=0;
  end else begin
   if(stream_prev_stall && (!tvalid || tdata!==stream_prev_data ||
      tkeep!==stream_prev_keep || tlast!==stream_prev_last))
    $fatal(1,"AXI STREAM STABILITY FAILURE");
   stream_prev_stall<=tvalid && !tready;
   stream_prev_data<=tdata;
   stream_prev_keep<=tkeep;
   stream_prev_last<=tlast;
   if(desc_prev_stall && (!desc_valid || desc_addr!==desc_prev_addr ||
      desc_len!==desc_prev_len || desc_tag!==desc_prev_tag))
    $fatal(1,"DMA DESCRIPTOR STABILITY FAILURE");
   desc_prev_stall<=desc_valid && !desc_ready;
   desc_prev_addr<=desc_addr;
   desc_prev_len<=desc_len;
   desc_prev_tag<=desc_tag;
  end
 end

 task run_stress_job;
  input [31:0] aa,bb;
  input integer a_first,b_first;
  integer old_desc,old_ar,old_status,old_stream,old_last,old_r;
  begin
   old_desc=desc_count; old_ar=ar_count; old_status=status_count;
   old_stream=stream_count; old_last=stream_last_count;old_r=r_count;
   successful_job(aa,bb,a_first,b_first);
   if(desc_count-old_desc!=2 || ar_count-old_ar!=2 ||
      status_count-old_status!=2 || stream_count-old_stream!=8 ||
      stream_last_count-old_last!=2 || r_count-old_r!=8)
    $fatal(1,"JOB COUNT MISMATCH desc=%0d ar=%0d status=%0d stream=%0d last=%0d r=%0d",
      desc_count-old_desc,ar_count-old_ar,status_count-old_status,
      stream_count-old_stream,stream_last_count-old_last,r_count-old_r);
   jobs_verified=jobs_verified+1;
   $display("STRESS JOB %0d PASSED",jobs_verified);
  end
 endtask

 initial begin
  repeat(5) @(negedge clk);rst_n=1;
  repeat(2) @(negedge clk);
  $display("STEP 9H-C: PSEUDORANDOM AXI STRESS REGRESSION seed=C0FFEE21");
  // Repeated jobs without reset.  Golden C is checked after every job.
  run_stress_job(32'h1000,32'h2000,1,21);
  run_stress_job(32'h3000,32'h4000,41,61);
  run_stress_job(32'h5000,32'h6000,81,101);
  run_stress_job(32'h3000,32'h2000,41,21);
  run_stress_job(32'h1000,32'h6000,1,101);
  run_stress_job(32'h5000,32'h4000,81,61);
  if(error_count!=0 || successful_jobs!=6 || jobs_verified!=6)
   $fatal(1,"FINAL COUNTS FAILED errors=%0d success=%0d verified=%0d",error_count,successful_jobs,jobs_verified);
  if(ar_stall_cycles==0 || r_stall_cycles==0)
   $fatal(1,"BACKPRESSURE NOT EXERCISED ar=%0d r=%0d",ar_stall_cycles,r_stall_cycles);
  $display("ALL STEP 9H-C RANDOMIZED STRESS TESTS PASSED");
  $display("Jobs=%0d Descriptors=%0d AR=%0d R=%0d Stream=%0d TLAST=%0d Status=%0d",
   jobs_verified,desc_count,ar_count,r_count,stream_count,stream_last_count,status_count);
  $display("AR_stall_cycles=%0d R_idle_cycles=%0d",ar_stall_cycles,r_stall_cycles);
  $finish;
 end
 initial begin #400000; $fatal(1,"GLOBAL TIMEOUT"); end
endmodule
