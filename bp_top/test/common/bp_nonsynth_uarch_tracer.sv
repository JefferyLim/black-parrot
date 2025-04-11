
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"
`include "bp_be_defines.svh"

module bp_nonsynth_uarch_tracer
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
	 `declare_bp_proc_params(bp_params_p)
     `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
     `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)

    , parameter uarch_trace_file_p = "uarch"
    )
   (input                         clk_i
    , input                       reset_i

    , input [`BSG_SAFE_CLOG2(num_core_p)-1:0] mhartid_i

    , input [issue_pkt_width_lp-1:0] issue_pkt_i
    , input [dispatch_pkt_width_lp-1:0] dispatch_pkt_i

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

  integer sched_file;
  string sched_fp;
  always_ff @(negedge reset_i)
    begin
      sched_file   = $sformatf("%s_%x.sched", uarch_trace_file_p, mhartid_i);
      sched_fp = $fopen(sched_file, "w");
      if (sched_fp)  $display("File was opened successfully : %0d", sched_fp);
              else     $display("File was NOT opened successfully : %0d", sched_fp);
      $fwrite(sched_file, "cycle count\n");
    end

  always_ff @(negedge clk_i)
    begin
      if (~reset_i & issue_pkt.v)
        $fwrite(sched_fp, "issue   : %0d, %x, %x,\n", cycle_cnt, issue_pkt.pc, fault);
      if (~reset_i & dispatch_pkt.v)
        $fwrite(sched_fp, "dispatch: %0d, %x, %x\n", cycle_cnt, dispatch_pkt.pc, dispatch_pkt.exception.mispredict);
      if (~reset_i & commit_pkt.instret)
        $fwrite(sched_fp, "commit: %0d,%x\n", cycle_cnt, commit_pkt.pc);
    end

  final
    begin
      $fwrite(sched_fp, "=============================\n");
      $fwrite(sched_fp, "Hello World:\n");
      $fclose(sched_fp);
    end

endmodule

