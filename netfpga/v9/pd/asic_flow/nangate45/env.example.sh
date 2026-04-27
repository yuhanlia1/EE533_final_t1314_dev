#!/usr/bin/env bash

# Copy this file to a local path, fill in the real Nangate45 library locations,
# then either source it directly or export ASIC_PLATFORM_CONFIG to that copy.

# If you already have an ORFS Nangate45 platform tree, set this and the flow
# will derive the default liberty/LEF paths from it.
export ASIC_PLATFORM_ROOT="/abs/path/to/OpenROAD-flow-scripts/flow/platforms/nangate45"

export ASIC_LIBERTY="${ASIC_PLATFORM_ROOT}/lib/NangateOpenCellLibrary_typical.lib"
export ASIC_TECH_LEF="${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.tech.lef"
export ASIC_STD_CELL_LEF="${ASIC_PLATFORM_ROOT}/lef/NangateOpenCellLibrary.macro.mod.lef"

export ASIC_SITE="FreePDK45_38x28_10R_NP_162NW_34O"
export ASIC_DIE_AREA="{0 0 3000 2500}"
export ASIC_CORE_AREA="{50 50 2950 2450}"
export ASIC_PLACE_DENSITY="0.55"

# Optional tool overrides.
# export YOSYS_BIN="/abs/path/to/yosys"
# export OPENROAD_BIN="/abs/path/to/openroad"
