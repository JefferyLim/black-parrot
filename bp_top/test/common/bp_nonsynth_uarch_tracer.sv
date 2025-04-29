
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"
`include "bp_be_defines.svh"

module bp_nonsynth_uarch_tracer
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
	 `declare_bp_proc_params(bp_params_p)

  , parameter assoc_p = 8
  , parameter sets_p = 64
  , parameter block_width_p = 512
  , parameter fill_width_p = 128
  , parameter trace_file_p = "dcache"
  , parameter tag_width_p = dcache_tag_width_p
  , parameter id_width_p = 1
   `declare_bp_be_dcache_engine_if_widths(paddr_width_p, tag_width_p, sets_p, assoc_p, dword_width_gp, block_width_p, fill_width_p, id_width_p)

     `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
     `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)
    , parameter uarch_trace_file_p = "uarch"
    )
   (input                         clk_i
    , input                       reset_i

    , input [`BSG_SAFE_CLOG2(num_core_p)-1:0] mhartid_i
	
    // Issue queue related signals
	, input [issue_pkt_width_lp-1:0] issue_pkt_i
    , input [dispatch_pkt_width_lp-1:0] dispatch_pkt_i
    , input fe_queue_read_i

	// Squash signal
    , input poison_isd_i

    // Instructions in the calculator pipelines
    , input [reservation_width_lp-1:0] reservation_i

	, input [3:0] exception_ecode_i
	// Memory Pipeline faults
    , input store_page_fault_v_i
    , input load_page_fault_v_i
	, input flush_i

	// Page Table Walker Privilege Faults
	, input priv_fault_i

    , input tlb_load_miss_v_i
    , input tlb_store_miss_v_i


	// Pipe System Information
    , input [decode_info_width_lp-1:0] decode_pkt_i
    , input [trans_info_width_lp-1:0] trans_pkt_i
    , input [retire_pkt_width_lp-1:0] retire_pkt_i
    , input [commit_pkt_width_lp-1:0] commit_pkt_i
	, input [wb_pkt_width_lp-1:0] late_wb_pkt_i


    //DCache

    , input cache_req_v_i
    , input cache_req_yumi_i
    , input cache_req_metadata_v_o
    , input [dcache_data_mem_pkt_width_lp-1:0]        data_mem_pkt_i
	, input data_mem_pkt_v_i
    , input data_mem_pkt_yumi_o
    , input wbuf_v_li
    , input wbuf_v_lo
    , input wbuf_yumi_li
	, input [dcache_req_width_lp-1:0]          cache_req_i

   , input [dpath_width_gp-1:0]    early_data_i
   , input                         early_v_i
   , input [dpath_width_gp-1:0]    final_data_i
   , input                         final_v_i

    );


  `declare_bp_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p);
  `declare_bp_be_dcache_engine_if(paddr_width_p, tag_width_p, sets_p, assoc_p, dword_width_gp, block_width_p, fill_width_p, id_width_p);

  bp_be_issue_pkt_s issue_pkt;
  assign issue_pkt = issue_pkt_i;

  logic [dispatch_pkt_width_lp-1:0] dispatch_pkt_D;

  bp_be_dispatch_pkt_s dispatch_pkt;
  assign dispatch_pkt = dispatch_pkt_D;

  bp_be_decode_info_s decode_pkt;
  assign decode_pkt = decode_pkt_i;
   
  bp_be_trans_info_s trans_pkt;
  assign trans_pkt = trans_pkt_i;

  bp_be_retire_pkt_s retire_pkt;
  assign retire_pkt = retire_pkt_i;
      
  bp_be_commit_pkt_s commit_pkt;
  assign commit_pkt = commit_pkt_i;

  bp_be_reservation_s reservation_pkt;
  assign reservation_pkt = reservation_i;

  bp_be_wb_pkt_s wb_pkt;
  assign wb_pkt = late_wb_pkt_i;
   
  bp_be_dcache_data_mem_pkt_s data_mem_pkt;
  assign data_mem_pkt = data_mem_pkt_i;


  bp_be_dcache_req_s cache_req_cast_i;
  assign cache_req_cast_i = cache_req_i;


  logic [29:0] cycle_cnt;
  bsg_counter_clear_up
   #(.max_val_p(2**30-1), .init_val_p(0))
   cycle_counter
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.clear_i(1'b0)
     ,.up_i(1'b1)
     ,.count_o(cycle_cnt)
     );

  logic fault;
  assign fault = issue_pkt.instr_access_fault | issue_pkt.instr_page_fault | issue_pkt.illegal_instr | issue_pkt.icache_miss;

  string sched_file;
  integer sched_fp;

  string pipe_mem_file;
  integer pipe_mem_fp;

  string trace_file;
  integer trace_fp;
  always_ff @(negedge reset_i)
    begin
      sched_file = $sformatf("%s_%x.sched", uarch_trace_file_p, mhartid_i);
      sched_fp = $fopen(sched_file, "w");
      if (sched_fp)  $display("file was opened successfully : %0d", sched_fp);
              else     $display("file was not opened successfully : %0d", sched_fp);

      pipe_mem_file = $sformatf("%s_%x.pipe_mem", uarch_trace_file_p, mhartid_i);
      pipe_mem_fp = $fopen(pipe_mem_file, "w");
      if (pipe_mem_fp)  $display("file was opened successfully : %0d", pipe_mem_fp);
              else     $display("file was not opened successfully : %0d", pipe_mem_fp);

      trace_file = $sformatf("%s_%x.trace", uarch_trace_file_p, mhartid_i);
      trace_fp = $fopen(trace_file, "w");
      if (trace_fp)  $display("file was opened successfully : %0d", trace_fp);
              else     $display("file was not opened successfully : %0d", trace_fp);



      $fwrite(sched_fp, "issue :cycle_cnt, issue_pkt.pc, fault, umode, smode, mmode\n");
      $fwrite(sched_fp, "dispatch: cycle_cnt, dispatch_pkt.pc, dispatch_pkt.v, dispatch_pkt.queue_v, poison_isd_i, dispatch_pkt.exception.mispredict\n");
      $fwrite(sched_fp, "commit: cycle_cnt, commit_pkt.pc\n");

    end

  always_ff @(negedge clk_i)
    begin
      if (~reset_i & issue_pkt.v)
        $fwrite(sched_fp, "issue   : %0d, %x, %x, %x, %x, %x\n", cycle_cnt, issue_pkt.pc, fault, decode_pkt.u_mode, decode_pkt.s_mode, decode_pkt.m_mode);
      if (~reset_i & fe_queue_read_i)
        $fwrite(sched_fp, "dispatch: %0d, %x, %x, %x, %x, %x\n", cycle_cnt, dispatch_pkt.pc, dispatch_pkt.v, dispatch_pkt.queue_v, poison_isd_i, dispatch_pkt.exception.mispredict);
      if (~reset_i & commit_pkt.instret)
        $fwrite(sched_fp, "commit (ret): %0d,%x, %x, %x\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);
      if (~reset_i & commit_pkt.exception)
        $fwrite(sched_fp, "commit (exc): %0d,%x, %x, %x\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);

	  if (~reset_i & flush_i)
		$fwrite(sched_fp, "flush: %0d\n", cycle_cnt);

    end

  // Get memory-related requests
  wire [dword_width_gp-1:0] rs1 = reservation_pkt.isrc1;
  wire [dword_width_gp-1:0] rs2 = reservation_pkt.isrc2;
  wire [dword_width_gp-1:0] imm = reservation_pkt.isrc3;

  wire is_req = reservation_pkt.v & (reservation_pkt.decode.pipe_mem_early_v | reservation_pkt.decode.pipe_mem_final_v);
 
  wire [rv64_eaddr_width_gp-1:0] eaddr = rs1 + imm;  

  always_ff @(negedge clk_i)
  begin
	if (~reset_i & is_req)
        $fwrite(pipe_mem_fp, "pipe_mem: %0d, %x, %x, %x, %x, %x, %x, %x\n", cycle_cnt, reservation_pkt.pc, reservation_pkt.decode.dcache_r_v, reservation_pkt.decode.dcache_w_v, eaddr, store_page_fault_v_i, load_page_fault_v_i, flush_i);
       
	if (~reset_i & (store_page_fault_v_i | load_page_fault_v_i))
		$fwrite(pipe_mem_fp, "pipe_mem: %0d, %x, %x\n", cycle_cnt, store_page_fault_v_i, load_page_fault_v_i);
  end

  always_ff @(posedge clk_i)
  begin
	if (~reset_i & wb_pkt.ptw_w_v)
		$fwrite(pipe_mem_fp, "ptw: %0d, %x, %x\n", cycle_cnt, wb_pkt.rd_addr,  wb_pkt.rd_data);
  end


  
  logic poison_isd_D; // 1 cycle delay of poison_isd

   bp_be_decode_s decode_D;
   bp_be_decode_s decode_DD;

string exc_str;
string priv_str;
string dispatch_str;

always_comb begin
    case (exception_ecode_i)
        4'h0: exc_str = "CAUSE_MISALIGNED_FETCH";
        4'h1: exc_str = "CAUSE_FETCH_ACCESS";
        4'h2: exc_str = "CAUSE_ILLEGAL_INSTRUCTION";
        4'h3: exc_str = "CAUSE_BREAKPOINT";
        4'h4: exc_str = "CAUSE_MISALIGNED_LOAD";
        4'h5: exc_str = "CAUSE_LOAD_ACCESS";
        4'h6: exc_str = "CAUSE_MISALIGNED_STORE";
        4'h7: exc_str = "CAUSE_STORE_ACCESS";
        4'h8: exc_str = "CAUSE_USER_ECALL";
        4'h9: exc_str = "CAUSE_SUPERVISOR_ECALL";
        4'ha: exc_str = "CAUSE_HYPERVISOR_ECALL";
        4'hb: exc_str = "CAUSE_MACHINE_ECALL";
        4'hc: exc_str = "CAUSE_FETCH_PAGE_FAULT";
        4'hd: exc_str = "CAUSE_LOAD_PAGE_FAULT";
        4'hf: exc_str = "CAUSE_STORE_PAGE_FAULT";
        default: exc_str = "UNKNOWN_CAUSE";
    endcase

    case (trans_pkt.priv_mode)
        	2'b00: priv_str = "user";
       		2'b01: priv_str = "supervisor";
        	2'b11: priv_str = "machine";
			default: priv_str = "ERROR";
	endcase


	dispatch_str = "";
 	if(dispatch_pkt.decode.dcache_mmu_v & dispatch_pkt.decode.fu_op == e_dcache_op_ptw)
		dispatch_str = "(ptw)";

end

  always_ff @(posedge clk_i)
  begin

	// Delay dispatch, because the reservation signal is 1 cycle delayed
	dispatch_pkt_D <= dispatch_pkt_i;
	poison_isd_D <= poison_isd_i;
	
	decode_D <= dispatch_pkt.decode;
	decode_DD <= decode_D;

	if (~reset_i)
	begin
      // Write only memory pipeline requests
	  if (dispatch_pkt.v & is_req)
		$fwrite(trace_fp, "%0d: dispatch %s: %x, %x, %x, %x, %s\n", cycle_cnt, dispatch_str, dispatch_pkt.pc, reservation_pkt.pc, dispatch_pkt.queue_v, eaddr, priv_str);

      // Whenever branch predictors/npc does not match expected
	  if (poison_isd_D)
		$fwrite(trace_fp, "%0d: poisoned: %x\n", cycle_cnt, issue_pkt.pc);

      // Whenever pipeline gets flushed
	  if (flush_i)
		$fwrite(trace_fp, "%0d: pipe flush\n", cycle_cnt);
	
      // Track all architecture instruction returns	
      if (commit_pkt.instret & (decode_DD.pipe_mem_early_v | decode_DD.pipe_mem_final_v))
        $fwrite(trace_fp, "%0d: commit (ret): %x, %x, %x (npc)\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);

      // Track all exceptions
      if (commit_pkt.exception)
        $fwrite(trace_fp, "%0d: commit (exc): %x, %x, %x, %s\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc, exc_str);
	
      // Track cache_req that leave dcache
	  if (cache_req_v_i)
		$fwrite(trace_fp, "%0d: cache: %x, %x, %x, (yumi) %x\n", cycle_cnt, cache_req_cast_i.addr, cache_req_cast_i.data, cache_req_cast_i.msg_type, cache_req_yumi_i);

	  // Track all data packets that come in
	  if (data_mem_pkt_v_i)
		$fwrite(trace_fp, "%0d: data_mem_pkt: %x\n", cycle_cnt,  data_mem_pkt.data);

      // Track all returns from memory pipe (including tlb misses
	  if(early_v_i)
		$fwrite(trace_fp, "%0d: pipe_mem (early): %x, (tlb load miss) %x, (tlb store miss) %x\n", cycle_cnt, early_data_i, tlb_load_miss_v_i, tlb_store_miss_v_i);
	  if(final_v_i)
		$fwrite(trace_fp, "%0d: pipe_mem (final): %x\n", cycle_cnt, final_data_i);
 
	end
  end

 
  final
    begin
      $fwrite(sched_fp, "=============================\n");
      $fwrite(sched_fp, "Hello World:\n");
      $fclose(sched_fp);
    end

endmodule

