# RSU ASIC Evaluation Pack

## Summary

- Top module: `user_top`
- Evaluation scope: `user_module_layer`
- Platform: `nangate45`
- Flow status: `postroute_complete_smoke_power_ready`
- Artifact root: `pd/asic_report`
- Clock target: `10.0 ns`
- Yosys in `PATH`: `yes`
- OpenROAD in `PATH`: `yes`
- Total memory bits discovered: `1273856`
- Logic area: `85840.062`
- Total macro + logic area: `972022.41`
- Placement WNS/TNS: `-57.37` / `-133879.56`
- CTS WNS/TNS: `-57.28` / `-133058.33`
- Route WNS/TNS: `-38.54` / `-38987.47`
- Power status: `smoke_power_ready`

## Scope

- Included modules: `action_dispatcher, alu_64_stage1, alu_64_stage2, ann_cpu_gpu_compute_core, ann_engine_wrapper, ann_feature_unpack, ann_task_ingress, arm_64_top, bf16_add_sub, bf16_mult, convertible_fifo, decode_stage1, ex_stage1, ex_stage2, fetch_stage1, fetch_stage2, fifo_bram, generic_regs, gpu_control, gpu_ex_mm_reg, gpu_ex_stage, gpu_id_ex_reg, gpu_id_stage, gpu_if_id_reg, gpu_if_stage, gpu_imem, gpu_mm_stage, gpu_mm_wb_reg, gpu_pc, gpu_shared_dmem, gpu_top_fifo_if, gpu_wb_stage, mem_RF, mem_data, mem_inst, mem_register_slice, mem_stage, packet_action_selector, user_top, wb_stage1`
- Excluded modules: `NetFPGA board shell, reference_core / DMA / MAC / SRAM controllers / DCM / IOB resources, user_data_path outer fabric`
- Missing external modules during closure walk: `none`

## Stage Directories

- Eval dir: `pd/asic_report/eval/user_top_eval`
- PNR dir: `pd/asic_report/pnr/user_top`
- Sim dir: `pd/asic_report/sim/user_top`
- Default post-route sim mode: `gate_level_sdf`
- Synth entrypoint: `pd/asic_report/eval/user_top_eval/run_yosys_synth.sh`
- OpenROAD entrypoint: `pd/asic_report/pnr/user_top/run_openroad.sh`
- Sim template: `pd/asic_report/sim/user_top/run_gatelevel_sdf_template.sh`

## Hierarchy Breakdown

| Group | Instances | Unique Modules | Memory Instances | Memory Bits |
| --- | ---: | ---: | ---: | ---: |
| Control Plane | 1 | 1 | 0 | 0 |
| Protocol / Flow | 6 | 4 | 2 | 36864 |
| ANN Wrapper | 4 | 4 | 1 | 18432 |
| Compute Core | 33 | 31 | 6 | 1218560 |
| Other | 1 | 1 | 0 | 0 |

## Memory Summary

| Instance Path | Module | Kind | Depth | Width | Bits | Ports |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `user_top/ingress_fifo/u_bram` | `fifo_bram` | fifo | 256 | 72 | 18432 | dual_port_rw |
| `user_top/egress_fifo/u_bram` | `fifo_bram` | fifo | 256 | 72 | 18432 | dual_port_rw |
| `user_top/ann_engine/ingress/packet_buf` | `fifo_bram` | fifo | 256 | 72 | 18432 | dual_port_rw |
| `user_top/ann_engine/compute_core/u_shared_dmem` | `gpu_shared_dmem` | shared_dmem | 16384 | 64 | 1048576 | dual_port_rw |
| `user_top/ann_engine/compute_core/arm_cpu/IF1/I_MEM` | `mem_inst` | instruction_memory | 512 | 32 | 16384 | single_port_rw |
| `user_top/ann_engine/compute_core/arm_cpu/ID1/REG_FILE` | `mem_RF` | register_file | 64 | 64 | 4096 | 1w_2r |
| `user_top/ann_engine/compute_core/arm_cpu/MEM/D_MEM` | `mem_data` | data_memory | 256 | 64 | 16384 | single_port_rw |
| `user_top/ann_engine/compute_core/arm_cpu/MEM/CTRL_MEM` | `mem_data` | data_memory | 256 | 8 | 2048 | single_port_rw |
| `user_top/ann_engine/compute_core/gpu_core/u_if/u_imem` | `gpu_imem` | instruction_memory | 4096 | 32 | 131072 | single_port_rw |

## Memory Implementation

| Instance Path | Implementation | Wrapper Strategy | Target Cells |
| --- | --- | --- | --- |
| `user_top/ingress_fifo/u_bram` | `placeholder_macro` | `direct_placeholder_wrapper` | `placeholder_fifo_bram_256x72_dp x1` |
| `user_top/egress_fifo/u_bram` | `placeholder_macro` | `direct_placeholder_wrapper` | `placeholder_fifo_bram_256x72_dp x1` |
| `user_top/ann_engine/ingress/packet_buf` | `placeholder_macro` | `direct_placeholder_wrapper` | `placeholder_fifo_bram_256x72_dp x1` |
| `user_top/ann_engine/compute_core/u_shared_dmem` | `placeholder_macro` | `direct_placeholder_wrapper` | `placeholder_gpu_shared_dmem_16384x64_dp x1` |
| `user_top/ann_engine/compute_core/arm_cpu/IF1/I_MEM` | `fakeram_wrapper` | `single_macro_zero_extended_addr` | `fakeram45_1024x32 x1` |
| `user_top/ann_engine/compute_core/arm_cpu/ID1/REG_FILE` | `placeholder_macro` | `direct_placeholder_wrapper` | `placeholder_mem_rf_64x64_1w2r x1` |
| `user_top/ann_engine/compute_core/arm_cpu/MEM/D_MEM` | `fakeram_wrapper` | `width_split_2x256x32` | `fakeram45_256x32 x2` |
| `user_top/ann_engine/compute_core/arm_cpu/MEM/CTRL_MEM` | `fakeram_wrapper` | `single_macro_padded_256x16` | `fakeram45_256x16 x1` |
| `user_top/ann_engine/compute_core/gpu_core/u_if/u_imem` | `fakeram_wrapper` | `banked_4x1024x32` | `fakeram45_1024x32 x4` |

- ASIC memory RTL: `pd/asic_report/eval/user_top_eval/user_top_memory_impl.v`
- Logic RTL filelist: `pd/asic_report/eval/user_top_eval/user_top_logic_sources.f`
- Fakeram cells used: `fakeram45_1024x32 x5, fakeram45_256x32 x2, fakeram45_256x16 x1`
- Placeholder macros used: `placeholder_fifo_bram_256x72_dp x3, placeholder_gpu_shared_dmem_16384x64_dp x1, placeholder_mem_rf_64x64_1w2r x1`

## Platform Inputs

- Platform root: `pd/asic_flow/nangate45`
- Missing required platform inputs: `none`
- Missing required tools: `none`
- Required env `ASIC_LIBERTY`: Path to the Nangate45 liberty file used by Yosys/OpenROAD.
- Required env `ASIC_TECH_LEF`: Path to the Nangate45 technology LEF.
- Required env `ASIC_STD_CELL_LEF`: Path to the Nangate45 standard-cell LEF.

## FPGA Baseline

- `core_clk` synthesis baseline: `9.679 ns / 103.315 MHz`
- Implemented whole-design baseline: `13.345 ns / 74.934 MHz`
- Device: `2vp50ff1152-7`
- Slices: `20330` / `23616`
- BRAMs: `108`
- MULT18X18: `11`
- Note: These are legacy NetFPGA Virtex-2 Pro FPGA baselines, not ASIC results.
- Note: The ASIC parameter pack uses them only as comparison anchors.

## Generated Files

- Yosys hierarchy script: `pd/asic_report/eval/user_top_eval/user_top_eval.ys`
- Yosys synth wrapper: `pd/asic_report/eval/user_top_eval/run_yosys_synth.sh`
- OpenROAD script: `pd/asic_report/pnr/user_top/openroad_flow.tcl`
- OpenROAD wrapper: `pd/asic_report/pnr/user_top/run_openroad.sh`
- Power estimation script: `pd/asic_report/pnr/user_top/power_estimation.tcl`
- Power estimation wrapper: `pd/asic_report/pnr/user_top/run_power_estimate.sh`
- SDC stub: `pd/asic_report/eval/user_top_eval/user_top_eval.sdc`
- Flow manifest: `pd/asic_report/eval/user_top_eval/flow_manifest.json`
- Macro placement TCL: `pd/asic_report/pnr/user_top/macro_placement.tcl`
- PNR README: `pd/asic_report/pnr/user_top/README.md`
- Sim README: `pd/asic_report/sim/user_top/README.md`

## Artifact Contract

- Memory implementation RTL: `pd/asic_report/eval/user_top_eval/user_top_memory_impl.v`
- Placeholder macro LEFs: `pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_fifo_bram_256x72_dp.lef, pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_gpu_shared_dmem_16384x64_dp.lef, pd/asic_report/eval/user_top_eval/generated_macros/lef/placeholder_mem_rf_64x64_1w2r.lef`
- Placeholder macro LIBs: `pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_fifo_bram_256x72_dp.lib, pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_gpu_shared_dmem_16384x64_dp.lib, pd/asic_report/eval/user_top_eval/generated_macros/lib/placeholder_mem_rf_64x64_1w2r.lib`
- Synthesized netlist: `pd/asic_report/eval/user_top_eval/user_top_synth.v`
- Synthesized design JSON: `pd/asic_report/eval/user_top_eval/user_top_synth.json`
- Post-route netlist: `pd/asic_report/pnr/user_top/results/user_top_postroute.v`
- Post-route SDF: `pd/asic_report/pnr/user_top/results/user_top_postroute.sdf`
- Post-route SPEF: `pd/asic_report/pnr/user_top/results/user_top_postroute.spef`
- Post-route power report: `pd/asic_report/pnr/user_top/reports/4_postroute_power.rpt`

## Area And Power

- Logic area status: `macro_plus_logic_available`
- Standard-cell logic area: `85840.062`
- Sequential area: `36948.73`
- Macro area: `885716.84`
- Total area: `972022.41`
- Utilization: `14.0`
- Power report path: `pd/asic_report/pnr/user_top/reports/4_postroute_power.rpt`
- Smoke post-route power total: `2.03e-02 W`
- Power activity hook env: `ASIC_POWER_ACTIVITY_TCL`
- Power note: Post-route power uses OpenROAD/OpenSTA report_power.
- Power note: RCX SPEF is extracted from the post-route DEF using Nangate45 `rcx_patterns.rules`.
- Power note: OpenSTA reports SPEF name-mismatch warnings around placeholder macro connectivity; treat the current number as demo-grade smoke power, not workload-aware final power.
- Power note: Provide switching activity through ASIC_POWER_ACTIVITY_TCL for workload-driven dynamic power.

## Notes

- The RSU ASIC pack treats user_top as the primary evaluation boundary.
- This flow is pinned to a Nangate45 teaching library baseline, not a signoff PDK.
- Small single-port memories are mapped through ASIC-only fakeram wrappers; complex memories stay as placeholder macros.
- user_data_path and NetFPGA board-facing modules remain out of the main RSU ASIC result.
- generic_regs is included through the local behavioral stub to keep user_top hierarchy closed.
- FPGA baselines come from pd/fpga_report.
