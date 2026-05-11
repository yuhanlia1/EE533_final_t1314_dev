#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v9/tmp/batch5_single_r01/captures"
scp node3@nf4.usc.edu:~/v8/batch5_single_r01_sender/captures/*.cap "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v9/tmp/batch5_single_r01/captures/"
