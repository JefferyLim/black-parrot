
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"
`include "bp_be_defines.svh"

module bp_nonsynth_arch_tracer
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
	 `declare_bp_proc_params(bp_params_p)
     `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
     `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)

    , parameter arch_trace_file_p = "arch"
    )
   (input                         clk_i
    , input                       reset_i

    , input [`BSG_SAFE_CLOG2(num_core_p)-1:0] mhartid_i

    , input [decode_info_width_lp-1:0] decode_pkt_i
    , input [trans_info_width_lp-1:0] trans_pkt_i
    , input [retire_pkt_width_lp-1:0] retire_pkt_i
    , input [commit_pkt_width_lp-1:0] commit_pkt_i
    );


  `declare_bp_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p);

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

  integer branch_histo [longint];
  integer miss_histo   [longint];

  integer instr_cnt;
  integer attaboy_cnt;
  integer redirect_cnt;
  integer br_cnt;
  integer jal_cnt;
  integer jalr_cnt;
  integer call_cnt;
  integer ret_cnt;
  integer btb_hit_cnt;
  integer ras_hit_cnt;
  integer bht_hit_cnt;

  integer file;
  string file_name;
  always_ff @(negedge reset_i)
    begin
      file_name = $sformatf("%s_%x.arch", example_trace_file_p, mhartid_i);
      file      = $fopen(file_name, "w");
    end

  always_ff @(negedge clk_i)
    begin
      if (~reset_i & commit_pkt.instret)
        $fwrite(file, "%0d,%x,%x,%x,%x,%x,%x, %s", cycle_cnt, decode_pkt.m_mode, decode_pkt.s_mode, decode_pkt.u_mode, trans_pkt.mstatus_sum, trans_pkt.mstatus_mxr , commit_pkt.pc, "instr");

      if (~reset_i)
        $fwrite(file, "\n");
    end

  final
    begin
      $fwrite(file, "=============================\n");
      $fwrite(file, "Hello World:\n");
    end

endmodule

