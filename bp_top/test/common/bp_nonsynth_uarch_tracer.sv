
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
	
    // Scheduler related signals
	, input [issue_pkt_width_lp-1:0] issue_pkt_i
    , input [dispatch_pkt_width_lp-1:0] dispatch_pkt_i
    , input fe_queue_read_i
    , input poison_isd_i //Squash signal

    // Calculator related signals
	, input [reservation_width_lp-1:0] reservation_i // Current PC in the calculator pipeline (1 delay after dispatch)

	, input [3:0] exception_ecode_i

	// Memory Pipeline faults
    , input store_page_fault_v_i
    , input load_page_fault_v_i
	, input flush_i
	, input [dword_width_gp-1:0] dcache_st_data_i

   	, input [dpath_width_gp-1:0] early_data_i
   	, input                      early_v_i
   	, input [dpath_width_gp-1:0] final_data_i
   	, input                      final_v_i

    //DCache
    , input cache_req_v_i
    , input cache_req_yumi_i
    , input cache_req_metadata_v_o
    , input [dcache_data_mem_pkt_width_lp-1:0] data_mem_pkt_i
	, input data_mem_pkt_v_i
    , input data_mem_pkt_yumi_o
    , input wbuf_v_li
    , input wbuf_v_lo
    , input wbuf_yumi_li
	, input [dcache_req_width_lp-1:0] cache_req_i

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


    );

  `declare_bp_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p);
  `declare_bp_be_dcache_engine_if(paddr_width_p, tag_width_p, sets_p, assoc_p, dword_width_gp, block_width_p, fill_width_p, id_width_p);

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

  string trace_file;
  integer trace_fp;
  always_ff @(negedge reset_i)
    begin
      trace_file = $sformatf("%s_%x.trace", uarch_trace_file_p, mhartid_i);
      trace_fp = $fopen(trace_file, "w");
      if (trace_fp)  $display("file was opened successfully : %0d", trace_fp);
              else     $display("file was not opened successfully : %0d", trace_fp);
    end

  // Get memory-related requests
  wire [dword_width_gp-1:0] rs1 = reservation_pkt.isrc1;
  wire [dword_width_gp-1:0] rs2 = reservation_pkt.isrc2;
  wire [dword_width_gp-1:0] imm = reservation_pkt.isrc3;

  wire is_req = reservation_pkt.v & (reservation_pkt.decode.pipe_mem_early_v | reservation_pkt.decode.pipe_mem_final_v); // Is this a memory request?

  wire [rv64_eaddr_width_gp-1:0] eaddr = rs1 + imm; // Address to read from

  logic poison_isd_D; // 1 cycle delay of poison_isd
  
  // Decode signal (2 cycle delay to keep track of memory requests in the pipeline)
  bp_be_decode_s decode_D;
  bp_be_decode_s decode_DD;
 
  // strings for trace information
  string exc_str;
  string priv_str;
  string dispatch_str;
  string cache_req_str;
  string dcache_str;
  string tlb_str;

  always_comb begin
	// Get the ecode
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

	// Get privilege mode
    case (trans_pkt.priv_mode)
        	2'b00: priv_str = "user";
       		2'b01: priv_str = "supervisor";
        	2'b11: priv_str = "machine";
			default: priv_str = "ERROR";
	endcase

	// Get cache_req type
	case(cache_req_cast_i.msg_type)
		4'b0000: cache_req_str = "miss_load";
  		4'b0001: cache_req_str = "miss_store";
	  	4'b0010: cache_req_str = "wt_store";
  		4'b0011: cache_req_str = "uc_load";
		4'b0100: cache_req_str = "uc_store";
	 	4'b0101: cache_req_str = "uc_amo";
  		4'b0110: cache_req_str = "cache_clean";
  		4'b0111: cache_req_str = "cache_inval";
  		4'b1000: cache_req_str = "cache_flush";
  		4'b1011: cache_req_str = "cache_bclean";
	  	4'b1100: cache_req_str = "cache_binval";
	  	4'b1101: cache_req_str = "cache_bflush";
  		default: cache_req_str = "unknown";
	endcase

	dcache_str = "";
	// Track store and load instructions in the memory pipeline
	if (is_req & dispatch_pkt.decode.dcache_r_v)
		dcache_str = "load";
	if (is_req & (dispatch_pkt.decode.dcache_w_v | dispatch_pkt.decode.dcache_cbo_v))
		dcache_str = "store";

	// Keep track of when we are doing a page table walk
	dispatch_str = "";
 	if(dispatch_pkt.decode.dcache_mmu_v & dispatch_pkt.decode.fu_op == e_dcache_op_ptw)
		dispatch_str = "(ptw)";

	// Determine dtlb state
	tlb_str = "";
	if(tlb_load_miss_v_i)
		tlb_str = "tlb_load_miss";

	if(tlb_store_miss_v_i)
		tlb_str = "tlb_store_miss";
  end

  always_ff @(posedge clk_i)
  begin

	// Delay dispatch, because the reservation signal is 1 cycle delayed
	dispatch_pkt_D <= dispatch_pkt_i;
	poison_isd_D <= poison_isd_i;

	// Delay decode to keep track of committed instruction type (we want to know what the instruction that is about to be committed)	
	decode_D <= dispatch_pkt.decode;
	decode_DD <= decode_D;

	if (~reset_i)
	begin
      // Write only memory pipeline requests
	  if (dispatch_pkt.v & is_req & dcache_str == "load") begin
		$fwrite(trace_fp, "%0d: dispatch %s: %x, %x, %s, %s\n", cycle_cnt, dispatch_str, dispatch_pkt.pc, eaddr, dcache_str, priv_str);
	  end else if (dispatch_pkt.v & is_req) begin
		$fwrite(trace_fp, "%0d: dispatch %s: %x, %x, %x, %s, %s\n", cycle_cnt, dispatch_str, dispatch_pkt.pc, eaddr, dcache_st_data_i, dcache_str, priv_str);
      end

      // Whenever branch predictors/npc does not match expected, it gets poisoned
	  if (poison_isd_D)
		$fwrite(trace_fp, "%0d: poisoned: %x\n", cycle_cnt, issue_pkt.pc);

      // Whenever pipeline gets flushed
	  if (flush_i)
		$fwrite(trace_fp, "%0d: pipe flush\n", cycle_cnt);
	
      // Track all architecture instruction returns that are memory instructions	
      if (commit_pkt.instret & (decode_DD.pipe_mem_early_v | decode_DD.pipe_mem_final_v))
        $fwrite(trace_fp, "%0d: commit (ret): %x, %x, %x (npc)\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);

      // Track all exceptions and what caused them
      if (commit_pkt.exception)
        $fwrite(trace_fp, "%0d: commit (exc): %x, %x, %x, %s\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc, exc_str);
	
      // Track cache_req that leave dcache and is accepted (yumi)
	  if (cache_req_v_i & cache_req_yumi_i)
		$fwrite(trace_fp, "%0d: cache: %x, %x, %s\n", cycle_cnt, cache_req_cast_i.addr, cache_req_cast_i.data, cache_req_str);
	  
	 // Track all data packets that come in
     // TODO: need to track the cache_req associatedf with this data_mem_pkt
	  if (data_mem_pkt_v_i)
		$fwrite(trace_fp, "%0d: data_mem_pkt: %x\n", cycle_cnt,  data_mem_pkt.data);

      // Track all data from memory pipe (This will include all PTW reads)
	  if(early_v_i)
		$fwrite(trace_fp, "%0d: pipe_mem (early): %x, %s\n", cycle_cnt, early_data_i, tlb_str);
	  if(final_v_i)
		$fwrite(trace_fp, "%0d: pipe_mem (final): %x\n", cycle_cnt, final_data_i);
 
	end
  end

 
  final
    begin
      $fclose(trace_fp);
    end

endmodule
