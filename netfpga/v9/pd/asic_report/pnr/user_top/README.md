# user_top PNR Run Root

This directory is the final OpenROAD physical-design baseline for `user_top`.

- `run_openroad.sh`: validates Nangate45 inputs and launches `openroad_flow.tcl`
- `run_power_estimate.sh`: reruns post-route power using `results/user_top_postroute.v/.spef`
- `macro_placement.tcl`: automatic macro packing rules for placeholder and fakeram macros
- `reports/`: final placement/CTS/route/power summaries used for demo reporting
- `results/`: preserved PnR artifacts; `user_top_postroute.*` is the final baseline and `user_top_preroute.*` is kept for before/after comparison
- `logs/`: tool logs
- `experiments/`: preserved parameter-sweep evidence (`density / halo / pad`) for later PPA and EPI comparisons

Current final demo baseline:

- `Logic area = 85840.062 um^2`
- `Total area = 972022.41 um^2`
- `Post-route WNS/TNS = -38.54 ns / -38987.47 ns`
- `Smoke post-route power = 2.03e-02 W`

Known limitations:

- timing is not closed at the current `10.0 ns` target
- power is currently smoke/demo-grade unless workload activity is injected through `ASIC_POWER_ACTIVITY_TCL`
- placeholder macro naming still causes some SPEF/OpenSTA mismatch warnings
