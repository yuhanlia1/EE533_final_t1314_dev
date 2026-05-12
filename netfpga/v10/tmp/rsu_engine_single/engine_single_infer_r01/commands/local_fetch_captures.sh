#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_engine_single/engine_single_infer_r01/captures"
scp node3@nf1.usc.edu:~/v8/engine_single_infer_r01_receiver/captures/*.cap "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_engine_single/engine_single_infer_r01/captures/"
