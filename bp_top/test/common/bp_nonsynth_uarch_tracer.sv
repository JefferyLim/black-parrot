
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"
`include "bp_be_defines.svh"

module bp_nonsynth_uarch_tracer
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
	 `declare_bp_proc_params(bp_params_p)
     `declare_bp_be_dcache_engine_if_widths(paddr_width_p, dcache_tag_width_p, dcache_sets_p, dcache_assoc_p, dword_width_gp, dcache_block_width_p, dcache_fill_width_p, dcache_req_id_width_p)
     `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
     `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)

    , parameter uarch_trace_file_p = "uarch"
    )
   (input                         clk_i
    , input                       reset_i

    , input [`BSG_SAFE_CLOG2(num_core_p)-1:0] mhartid_i

    , input [issue_pkt_width_lp-1:0] issue_pkt_i
    , input [dispatch_pkt_width_lp-1:0] dispatch_pkt_i
    , input fe_queue_read_i
    , input poison_isd_i

    , input [reservation_width_lp-1:0] reservation_i
    , input store_access_fault_v_i
    , input load_access_fault_v_i
	, input flush_i

	, input priv_fault_i

    , input [decode_info_width_lp-1:0] decode_pkt_i
    , input [trans_info_width_lp-1:0] trans_pkt_i
    , input [retire_pkt_width_lp-1:0] retire_pkt_i
    , input [commit_pkt_width_lp-1:0] commit_pkt_i
    );


  `declare_bp_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p);

  bp_be_issue_pkt_s issue_pkt;
  assign issue_pkt = issue_pkt_i;

  bp_be_dispatch_pkt_s dispatch_pkt;
  assign dispatch_pkt = dispatch_pkt_i;

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
        $fwrite(sched_fp, "commit: %0d,%x, %x, %x\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);
      if (~reset_i & commit_pkt.exception)
        $fwrite(sched_fp, "commit: %0d,%x, %x, %x\n", cycle_cnt, commit_pkt.pc, commit_pkt.npc_w_v, commit_pkt.npc);
    end

  wire [dword_width_gp-1:0] rs1 = reservation_pkt.isrc1;
  wire [dword_width_gp-1:0] rs2 = reservation_pkt.isrc2;
  wire [dword_width_gp-1:0] imm = reservation_pkt.isrc3;

  wire is_req = reservation_pkt.v & (reservation_pkt.decode.pipe_mem_early_v | reservation_pkt.decode.pipe_mem_final_v);
  wire [rv64_eaddr_width_gp-1:0] eaddr = rs1 + imm;
  

  always_ff @(negedge clk_i)
  begin
	if (~reset_i & is_req)
        $fwrite(pipe_mem_fp, "pipe_mem: %0d, %x, %x, %x, %x, %x, %x, %x\n", cycle_cnt, reservation_pkt.pc, reservation_pkt.decode.dcache_r_v, reservation_pkt.decode.dcache_w_v, eaddr, store_access_fault_v_i, load_access_fault_v_i, flush_i);
       
	if (~reset_i & (store_access_fault_v_i | load_access_fault_v_i))
		$fwrite(pipe_mem_fp, "pipe_mem: %0d, %x, %x\n", cycle_cnt, store_access_fault_v_i, load_access_fault_v_i);
  end

  always_ff @(posedge clk_i or negedge clk_i)
  begin
	if (~reset_i & (priv_fault_i))
		$fwrite(pipe_mem_fp, "page table walker: %0d, %x, %x, %x, %x\n", cycle_cnt, dispatch_pkt.pc, priv_fault_i,	dispatch_pkt.exception.store_page_fault, dispatch_pkt.exception.load_page_fault);
  end

 
  final
    begin
      $fwrite(sched_fp, "=============================\n");
      $fwrite(sched_fp, "Hello World:\n");
      $fclose(sched_fp);
    end

endmodule

