# Other Pros Rate-Scan Summary

- run_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_other_pros`
- config_path: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/scripts/board/rsu_demo_other_pros_rate.json`
- init_run_dir: `other_pros_rate_init_board`
- rate_points_req_per_sec: `[6500]`
- send_duration_seconds: `2.0`
- drain_timeout_seconds: `1.0`
- allow_fallback: `False`
- max_zero_loss_pps: `None`
- first_overload_pps: `6500.0`
- threshold_complete: `True`
- overall_verdict: `FAIL`
- recommended_figure: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/bt/system_report/figures/rate_scan_energy_validity.png`

| Rate (pps) | Verdict | Valid | Drops | Mismatch | Goodput | RateCtrl |
| --- | --- | --- | --- | --- | --- | --- |
| 6500.0 | FAIL | no | 827 | 827 | 5728.345 | paced_pcap_single_replay |
