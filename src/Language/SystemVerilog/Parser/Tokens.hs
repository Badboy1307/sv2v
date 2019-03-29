module Language.SystemVerilog.Parser.Tokens
  ( Token     (..)
  , TokenName (..)
  , Position  (..)
  , tokenString
  ) where

import Text.Printf

tokenString :: Token -> String
tokenString (Token _ s _) = s

data Position = Position String Int Int deriving Eq

instance Show Position where
  show (Position f l c) = printf "%s:%d:%d" f l c

data Token = Token TokenName String Position deriving (Show, Eq)

data TokenName
  = KW_alias
  | KW_always
  | KW_always_comb
  | KW_always_ff
  | KW_always_latch
  | KW_and
  | KW_assert
  | KW_assign
  | KW_assume
  | KW_automatic
  | KW_before
  | KW_begin
  | KW_bind
  | KW_bins
  | KW_binsof
  | KW_bit
  | KW_break
  | KW_buf
  | KW_bufif0
  | KW_bufif1
  | KW_byte
  | KW_case
  | KW_casex
  | KW_casez
  | KW_cell
  | KW_chandle
  | KW_class
  | KW_clocking
  | KW_cmos
  | KW_config
  | KW_const
  | KW_constraint
  | KW_context
  | KW_continue
  | KW_cover
  | KW_covergroup
  | KW_coverpoint
  | KW_cross
  | KW_deassign
  | KW_default
  | KW_defparam
  | KW_design
  | KW_disable
  | KW_dist
  | KW_do
  | KW_edge
  | KW_else
  | KW_end
  | KW_endcase
  | KW_endclass
  | KW_endclocking
  | KW_endconfig
  | KW_endfunction
  | KW_endgenerate
  | KW_endgroup
  | KW_endinterface
  | KW_endmodule
  | KW_endpackage
  | KW_endprimitive
  | KW_endprogram
  | KW_endproperty
  | KW_endspecify
  | KW_endsequence
  | KW_endtable
  | KW_endtask
  | KW_enum
  | KW_event
  | KW_expect
  | KW_export
  | KW_extends
  | KW_extern
  | KW_final
  | KW_first_match
  | KW_for
  | KW_force
  | KW_foreach
  | KW_forever
  | KW_fork
  | KW_forkjoin
  | KW_function
  | KW_function_prototype
  | KW_generate
  | KW_genvar
  | KW_highz0
  | KW_highz1
  | KW_if
  | KW_iff
  | KW_ifnone
  | KW_ignore_bins
  | KW_illegal_bins
  | KW_import
  | KW_incdir
  | KW_include
  | KW_initial
  | KW_inout
  | KW_input
  | KW_inside
  | KW_instance
  | KW_int
  | KW_integer
  | KW_interface
  | KW_intersect
  | KW_join
  | KW_join_any
  | KW_join_none
  | KW_large
  | KW_liblist
  | KW_library
  | KW_local
  | KW_localparam
  | KW_logic
  | KW_longint
  | KW_macromodule
  | KW_matches
  | KW_medium
  | KW_modport
  | KW_module
  | KW_nand
  | KW_negedge
  | KW_new
  | KW_nmos
  | KW_nor
  | KW_noshowcancelled
  | KW_not
  | KW_notif0
  | KW_notif1
  | KW_null
  | KW_option
  | KW_or
  | KW_output
  | KW_package
  | KW_packed
  | KW_parameter
  | KW_pathpulse_dollar
  | KW_pmos
  | KW_posedge
  | KW_primitive
  | KW_priority
  | KW_program
  | KW_property
  | KW_protected
  | KW_pull0
  | KW_pull1
  | KW_pulldown
  | KW_pullup
  | KW_pulsestyle_onevent
  | KW_pulsestyle_ondetect
  | KW_pure
  | KW_rand
  | KW_randc
  | KW_randcase
  | KW_randsequence
  | KW_rcmos
  | KW_real
  | KW_realtime
  | KW_ref
  | KW_reg
  | KW_release
  | KW_repeat
  | KW_return
  | KW_rnmos
  | KW_rpmos
  | KW_rtran
  | KW_rtranif0
  | KW_rtranif1
  | KW_scalared
  | KW_sequence
  | KW_shortint
  | KW_shortreal
  | KW_showcancelled
  | KW_signed
  | KW_small
  | KW_solve
  | KW_specify
  | KW_specparam
  | KW_static
  | KW_strength0
  | KW_strength1
  | KW_string
  | KW_strong0
  | KW_strong1
  | KW_struct
  | KW_super
  | KW_supply0
  | KW_supply1
  | KW_table
  | KW_tagged
  | KW_task
  | KW_this
  | KW_throughout
  | KW_time
  | KW_timeprecision
  | KW_timeunit
  | KW_tran
  | KW_tranif0
  | KW_tranif1
  | KW_tri
  | KW_tri0
  | KW_tri1
  | KW_triand
  | KW_trior
  | KW_trireg
  | KW_type
  | KW_typedef
  | KW_type_option
  | KW_union
  | KW_unique
  | KW_unsigned
  | KW_use
  | KW_uwire
  | KW_var
  | KW_vectored
  | KW_virtual
  | KW_void
  | KW_wait
  | KW_wait_order
  | KW_wand
  | KW_weak0
  | KW_weak1
  | KW_while
  | KW_wildcard
  | KW_wire
  | KW_with
  | KW_within
  | KW_wor
  | KW_xnor
  | KW_xor
  | Id_simple
  | Id_escaped
  | Id_system
  | Lit_number_unsigned
  | Lit_number
  | Lit_string
  | Sym_paren_l
  | Sym_paren_r
  | Sym_brack_l
  | Sym_brack_r
  | Sym_brace_l
  | Sym_brace_r
  | Sym_tildy
  | Sym_bang
  | Sym_at
  | Sym_pound
  | Sym_percent
  | Sym_hat
  | Sym_amp
  | Sym_bar
  | Sym_aster
  | Sym_dot
  | Sym_comma
  | Sym_colon
  | Sym_semi
  | Sym_eq
  | Sym_lt
  | Sym_gt
  | Sym_plus
  | Sym_dash
  | Sym_question
  | Sym_slash
  | Sym_dollar
  | Sym_s_quote
  | Sym_tildy_amp
  | Sym_tildy_bar
  | Sym_tildy_hat
  | Sym_hat_tildy
  | Sym_eq_eq
  | Sym_bang_eq
  | Sym_amp_amp
  | Sym_bar_bar
  | Sym_aster_aster
  | Sym_lt_eq
  | Sym_gt_eq
  | Sym_gt_gt
  | Sym_lt_lt
  | Sym_plus_plus
  | Sym_dash_dash
  | Sym_plus_eq
  | Sym_dash_eq
  | Sym_aster_eq
  | Sym_slash_eq
  | Sym_percent_eq
  | Sym_amp_eq
  | Sym_bar_eq
  | Sym_hat_eq
  | Sym_plus_colon
  | Sym_dash_colon
  | Sym_colon_colon
  | Sym_dot_aster
  | Sym_dash_gt
  | Sym_colon_eq
  | Sym_colon_slash
  | Sym_pound_pound
  | Sym_brack_l_aster
  | Sym_brack_l_eq
  | Sym_eq_gt
  | Sym_at_aster
  | Sym_paren_l_aster
  | Sym_aster_paren_r
  | Sym_aster_gt
  | Sym_eq_eq_eq
  | Sym_bang_eq_eq
  | Sym_eq_eq_question
  | Sym_bang_eq_question
  | Sym_gt_gt_gt
  | Sym_lt_lt_lt
  | Sym_lt_lt_eq
  | Sym_gt_gt_eq
  | Sym_bar_dash_gt
  | Sym_bar_eq_gt
  | Sym_brack_l_dash_gt
  | Sym_at_at_paren_l
  | Sym_paren_l_aster_paren_r
  | Sym_dash_gt_gt
  | Sym_amp_amp_amp
  | Sym_lt_lt_lt_eq
  | Sym_gt_gt_gt_eq
  | Spe_Directive
  | Spe_Newline
  | Unknown
  deriving (Show, Eq)
