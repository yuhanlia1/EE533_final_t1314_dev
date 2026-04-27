# Auto-generated OpenROAD baseline for nangate45.
# Expected wrapper entrypoint: pd/asic_report/pnr/user_top/run_openroad.sh

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

proc ensure_env_default {name default_value} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    set ::env($name) $default_value
  }
}

proc source_env_tcl_if_present {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    return
  }
  source_if_exists [file normalize $::env($name)]
}

proc repair_tie_fanout_if_enabled {} {
  if {$::env(SKIP_REPAIR_TIE_FANOUT)} {
    puts "Skipping repair_tie_fanout because SKIP_REPAIR_TIE_FANOUT is set."
    return
  }
  foreach {tie_var tie_label} {TIELO_CELL_AND_PORT lo TIEHI_CELL_AND_PORT hi} {
    set tie_spec $::env($tie_var)
    set tie_cell_name [lindex $tie_spec 0]
    set tie_pin_name [lindex $tie_spec 1]
    set tie_lib_cells [get_lib_cell $tie_cell_name]
    if {[llength $tie_lib_cells] == 0} {
      puts stderr "error: unable to resolve tie cell $tie_cell_name from $tie_var"
      exit 2
    }
    set tie_lib_name [get_name [get_property [lindex $tie_lib_cells 0] library]]
    set tie_pin "${tie_lib_name}/${tie_cell_name}/${tie_pin_name}"
    puts "Repair tie $tie_label fanout using $tie_pin ..."
    repair_tie_fanout -separation $::env(TIE_SEPARATION) $tie_pin
  }
}

proc normalize_tie_constant_nets {} {
  set block [[[ord::get_db] getChip] getBlock]
  set converted_count 0
  foreach dbnet [$block getNets] {
    set sig_type [$dbnet getSigType]
    if {$sig_type ni {GROUND POWER}} {
      continue
    }
    if {[$dbnet isSpecial]} {
      continue
    }
    set iterm_count [llength [$dbnet getITerms]]
    set bterm_count [llength [$dbnet getBTerms]]
    if {$iterm_count != 0 || $bterm_count != 0} {
      continue
    }
    puts "Converting constant net [$dbnet getName] from $sig_type to SIGNAL."
    $dbnet setSigType SIGNAL
    incr converted_count
  }
  puts "Converted $converted_count constant POWER/GROUND nets to SIGNAL."
}

set run_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $run_dir ../../../..]]
set design_name user_top
set top_module user_top
set synthesized_netlist [file normalize [file join $repo_root pd/asic_report/eval/user_top_eval/user_top_synth.v]]
set sdc_file [file normalize [file join $repo_root pd/asic_report/eval/user_top_eval/user_top_eval.sdc]]
set macro_placement_tcl [file normalize [file join $repo_root pd/asic_report/pnr/user_top/macro_placement.tcl]]
set report_dir [file normalize [file join $run_dir reports]]
set result_dir [file normalize [file join $run_dir results]]
set log_dir [file normalize [file join $run_dir logs]]

file mkdir $report_dir
file mkdir $result_dir
file mkdir $log_dir

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
  ensure_env_default RCX_RULES [file join $platform_root rcx_patterns.rules]
}
set site [env_or_default ASIC_SITE "FreePDK45_38x28_10R_NP_162NW_34O"]
set die_area [env_or_default ASIC_DIE_AREA "0 0 3000 2500"]
set core_area [env_or_default ASIC_CORE_AREA "50 50 2950 2450"]
set place_density [env_or_default ASIC_PLACE_DENSITY "0.55"]

ensure_env_default TAP_CELL_NAME TAPCELL_X1
ensure_env_default MIN_ROUTING_LAYER metal2
ensure_env_default MIN_CLK_ROUTING_LAYER metal4
ensure_env_default MAX_ROUTING_LAYER metal10
ensure_env_default IO_PLACER_H metal5
ensure_env_default IO_PLACER_V metal6
ensure_env_default VIA_IN_PIN_MIN_LAYER metal1
ensure_env_default VIA_IN_PIN_MAX_LAYER metal3
ensure_env_default TIEHI_CELL_AND_PORT {LOGIC1_X1 Z}
ensure_env_default TIELO_CELL_AND_PORT {LOGIC0_X1 Z}
ensure_env_default TIE_SEPARATION 0
ensure_env_default SKIP_REPAIR_TIE_FANOUT 0
ensure_env_default DONT_USE_CELLS {TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1}
ensure_env_default CELL_PAD_IN_SITES_DETAIL_PLACEMENT 0
ensure_env_default RECOVER_POWER 0
ensure_env_default MACRO_PLACE_HALO_WIDTH 20
ensure_env_default MACRO_PLACE_HALO_HEIGHT 20
ensure_env_default DETAILED_ROUTE_END_ITERATION 64
ensure_env_default DETAILED_ROUTE_VERBOSE 1
ensure_env_default REPAIR_PDN_VIAS 0

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

if {![file exists $synthesized_netlist]} {
  puts stderr "error: synthesized netlist not found at $synthesized_netlist; run pd/asic_report/eval/user_top_eval/run_yosys_synth.sh first"
  exit 2
}

read_lef $tech_lef
read_lef $stdcell_lef
foreach lef $additional_lefs {
  read_lef $lef
}
read_liberty $liberty_file
foreach liberty $additional_libs {
  read_liberty $liberty
}
read_verilog $synthesized_netlist
link_design $top_module
read_sdc $sdc_file
if {$::env(DONT_USE_CELLS) ne ""} {
  set_dont_use $::env(DONT_USE_CELLS)
}

initialize_floorplan -die_area $die_area -core_area $core_area -site $site
if {[file exists [file join $platform_root make_tracks.tcl]]} {
  source [file join $platform_root make_tracks.tcl]
} else {
  make_tracks
}
source_if_exists [file join $platform_root setRC.tcl]
source_if_exists [file join $platform_root fastroute.tcl]
repair_tie_fanout_if_enabled
normalize_tie_constant_nets
source_if_exists $macro_placement_tcl
place_pins -hor_layers $::env(IO_PLACER_H) -ver_layers $::env(IO_PLACER_V)
source_if_exists [file join $platform_root tapcell.tcl]
source_if_exists [file join $platform_root grid_strategy-M1-M4-M7.tcl]
pdngen
global_placement -density $place_density
detailed_placement
check_placement -verbose
estimate_parasitics -placement
report_design_area > [file join $report_dir 1_placement_design_area.rpt]
report_worst_slack > [file join $report_dir 1_placement_worst_slack.rpt]
report_tns > [file join $report_dir 1_placement_tns.rpt]

repair_clock_inverters
clock_tree_synthesis -sink_clustering_enable -repair_clock_nets
set_placement_padding -global -left $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT) -right $::env(CELL_PAD_IN_SITES_DETAIL_PLACEMENT)
detailed_placement
check_placement -verbose
set_propagated_clock [all_clocks]
estimate_parasitics -placement
report_worst_slack > [file join $report_dir 2_cts_worst_slack.rpt]
report_tns > [file join $report_dir 2_cts_tns.rpt]

normalize_tie_constant_nets
pin_access -via_in_pin_bottom_layer $::env(VIA_IN_PIN_MIN_LAYER) -via_in_pin_top_layer $::env(VIA_IN_PIN_MAX_LAYER)
global_route -congestion_report_file [file join $report_dir 3_route_congestion.rpt]
write_def [file join $result_dir user_top_preroute.def]
write_verilog [file join $result_dir user_top_preroute.v]
set detailed_route_args [list \
  -output_drc [file join $report_dir 3_route_drc.rpt] \
  -output_maze [file join $result_dir 3_route_maze.log] \
  -via_in_pin_bottom_layer $::env(VIA_IN_PIN_MIN_LAYER) \
  -via_in_pin_top_layer $::env(VIA_IN_PIN_MAX_LAYER) \
  -droute_end_iter $::env(DETAILED_ROUTE_END_ITERATION) \
  -verbose $::env(DETAILED_ROUTE_VERBOSE)]
if {$::env(REPAIR_PDN_VIAS)} {
  lappend detailed_route_args -repair_pdn_vias 1
}
eval detailed_route $detailed_route_args
if {[info exists ::env(RCX_RULES)] && $::env(RCX_RULES) ne "" && [file exists $::env(RCX_RULES)]} {
  define_process_corner -ext_model_index 0 X
  extract_parasitics -ext_model_file $::env(RCX_RULES)
  write_spef [file join $result_dir user_top_postroute.spef]
  read_spef [file join $result_dir user_top_postroute.spef]
} else {
  estimate_parasitics -global_routing
}
source_env_tcl_if_present ASIC_POWER_ACTIVITY_TCL
report_checks -path_delay min_max -format full_clock_expanded > [file join $report_dir 3_route_checks.rpt]
report_design_area > [file join $report_dir 3_route_design_area.rpt]
report_worst_slack > [file join $report_dir 3_route_worst_slack.rpt]
report_tns > [file join $report_dir 3_route_tns.rpt]
report_power > [file join $report_dir 4_postroute_power.rpt]

write_def [file join $result_dir user_top_postroute.def]
write_verilog [file join $result_dir user_top_postroute.v]
write_sdf [file join $result_dir user_top_postroute.sdf]

# Default planning target from the RSU ASIC parameter pack:
#   core_clk period = 10.000 ns
# Default PNR root:
#   pd/asic_report/pnr/user_top
