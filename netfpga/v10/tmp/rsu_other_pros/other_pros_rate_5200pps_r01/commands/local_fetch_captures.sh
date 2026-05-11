#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_other_pros/other_pros_rate_5200pps_r01/captures"
scp node4@nf7.usc.edu:~/v8/other_pros_rate_5200pps_r01_receiver/captures/*.cap "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_other_pros/other_pros_rate_5200pps_r01/captures/"
