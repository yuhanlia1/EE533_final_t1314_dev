#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_zero_copy_demo/captures"
scp node4@nf7.usc.edu:~/v8/rsu_zero_copy_demo_receiver/captures/*.cap "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_zero_copy_demo/captures/"
