# Auto-generated macro placement guidance for user_top.
# This baseline keeps macro placement automatic but exposes the main route
# convergence knobs through environment variables.

if {[info exists ::env(MACRO_PLACE_HALO_WIDTH)] && $::env(MACRO_PLACE_HALO_WIDTH) ne ""} {
  set macro_halo_width $::env(MACRO_PLACE_HALO_WIDTH)
} else {
  set macro_halo_width 20
}

if {[info exists ::env(MACRO_PLACE_HALO_HEIGHT)] && $::env(MACRO_PLACE_HALO_HEIGHT) ne ""} {
  set macro_halo_height $::env(MACRO_PLACE_HALO_HEIGHT)
} else {
  set macro_halo_height 20
}

if {[info exists ::env(MACRO_PLACE_TARGET_UTIL)] && $::env(MACRO_PLACE_TARGET_UTIL) ne ""} {
  set macro_target_util $::env(MACRO_PLACE_TARGET_UTIL)
} else {
  set macro_target_util $place_density
}

rtl_macro_placer -halo_width $macro_halo_width -halo_height $macro_halo_height -target_util $macro_target_util
