# Nangate45 Flow Inputs

This directory defines the external input contract for the `user_top` ASIC baseline flow.

The repository does not vendor the full Nangate45 platform into `pd/`, but it can consume an existing ORFS `nangate45` platform root and derive the standard cell and fakeram collateral from it.

Required variables:

- `ASIC_PLATFORM_ROOT`: optional Nangate45 platform root; if set, the flow auto-derives the default liberty and LEF paths
- `ASIC_LIBERTY`: Nangate45 liberty file used by Yosys and OpenROAD
- `ASIC_TECH_LEF`: technology LEF
- `ASIC_STD_CELL_LEF`: standard-cell LEF

Common optional variables:

- `ASIC_SITE`: defaults to `FreePDK45_38x28_10R_NP_162NW_34O`
- `ASIC_DIE_AREA`: defaults to `{0 0 3000 2500}`
- `ASIC_CORE_AREA`: defaults to `{50 50 2950 2450}`
- `ASIC_PLACE_DENSITY`: defaults to `0.55`
- `YOSYS_BIN`: optional Yosys binary override
- `OPENROAD_BIN`: optional OpenROAD binary override

Recommended flow:

1. Copy `env.example.sh` to a local file outside version control and update the library paths.
2. `source` that file or export `ASIC_PLATFORM_CONFIG` to it.
3. Run `python3 scripts/asic/generate_rsu_eval.py --platform nangate45`.
4. Run `pd/asic_report/eval/user_top_eval/run_yosys_synth.sh`.
5. Run `pd/asic_report/pnr/user_top/run_openroad.sh`.
