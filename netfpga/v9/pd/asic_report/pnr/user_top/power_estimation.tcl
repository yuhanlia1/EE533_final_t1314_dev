# Auto-generated post-route power estimation helper for nangate45.

proc require_env {name description} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    puts stderr "error: missing environment variable $name ($description)"
    exit 2
  }
}

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc source_if_exists {path} {
  if {[file exists $path]} {
    uplevel #0 [list source $path]
  }
}

proc source_env_tcl_if_present {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    return
  }
  source_if_exists [file normalize $::env($name)]
}

set run_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $run_dir ../../../..]]
set top_module user_top
set sdc_file [file normalize [file join $repo_root pd/asic_report/eval/user_top_eval/user_top_eval.sdc]]
set postroute_def [file normalize [file join $run_dir results user_top_postroute.def]]
set postroute_netlist [file normalize [file join $run_dir results user_top_postroute.v]]
set postroute_spef [file normalize [file join $run_dir results user_top_postroute.spef]]
set report_dir [file normalize [file join $run_dir reports]]
set report_file [file normalize [file join $report_dir 4_postroute_power.rpt]]

require_env ASIC_LIBERTY "standard-cell liberty"
require_env ASIC_TECH_LEF "technology LEF"
require_env ASIC_STD_CELL_LEF "standard-cell LEF"

set liberty_file $::env(ASIC_LIBERTY)
set tech_lef $::env(ASIC_TECH_LEF)
set stdcell_lef $::env(ASIC_STD_CELL_LEF)
if {[info exists ::env(ASIC_PLATFORM_ROOT)] && $::env(ASIC_PLATFORM_ROOT) ne ""} {
  set platform_root [file normalize $::env(ASIC_PLATFORM_ROOT)]
} else {
  set platform_root [file normalize [file dirname [file dirname $tech_lef]]]
}
if {[file exists [file join $platform_root rcx_patterns.rules]]} {
  if {![info exists ::env(RCX_RULES)] || $::env(RCX_RULES) eq ""} {
    set ::env(RCX_RULES) [file join $platform_root rcx_patterns.rules]
  }
}

set additional_lefs [list]
foreach cell_name [list fakeram45_1024x32 fakeram45_256x16 fakeram45_256x32] {
  lappend additional_lefs [file join $platform_root lef "${cell_name}.lef"]
}
foreach lef [list [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_fifo_bram_256x72_dp.lef] [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_gpu_shared_dmem_16384x64_dp.lef] [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_mem_rf_64x64_1w2r.lef]] {
  lappend additional_lefs $lef
}

set additional_libs [list]
foreach cell_name [list fakeram45_1024x32 fakeram45_256x16 fakeram45_256x32] {
  lappend additional_libs [file join $platform_root lib "${cell_name}.lib"]
}
foreach liberty [list [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_fifo_bram_256x72_dp.lib] [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_gpu_shared_dmem_16384x64_dp.lib] [file join $repo_root pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_mem_rf_64x64_1w2r.lib]] {
  lappend additional_libs $liberty
}

if {![file exists $postroute_netlist]} {
  puts stderr "error: missing post-route netlist $postroute_netlist"
  exit 2
}
if {![file exists $postroute_spef] && ![file exists $postroute_def]} {
  puts stderr "error: missing both post-route SPEF $postroute_spef and DEF $postroute_def"
  exit 2
}

file mkdir $report_dir

read_lef $tech_lef
read_lef $stdcell_lef
foreach lef $additional_lefs {
  read_lef $lef
}
read_liberty $liberty_file
foreach liberty $additional_libs {
  read_liberty $liberty
}
if {[file exists $postroute_def]} {
  read_def $postroute_def
} else {
  read_verilog $postroute_netlist
  link_design $top_module
}
read_sdc $sdc_file
if {[file exists $postroute_spef]} {
  read_spef $postroute_spef
} elseif {[info exists ::env(RCX_RULES)] && $::env(RCX_RULES) ne "" && [file exists $::env(RCX_RULES)] && [file exists $postroute_def]} {
  define_process_corner -ext_model_index 0 X
  extract_parasitics -ext_model_file $::env(RCX_RULES)
  write_spef $postroute_spef
  read_spef $postroute_spef
} else {
  estimate_parasitics -global_routing
}
set_propagated_clock [all_clocks]
source_env_tcl_if_present ASIC_POWER_ACTIVITY_TCL
report_power > $report_file
puts "wrote $report_file"
