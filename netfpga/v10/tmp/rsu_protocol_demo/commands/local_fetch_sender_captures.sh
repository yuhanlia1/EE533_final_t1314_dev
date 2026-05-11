#!/usr/bin/env bash
set -euo pipefail
mkdir -p "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_protocol_demo/captures"
scp node4@nf5.usc.edu:~/v8/rsu_protocol_demo_sender/captures/*.cap "/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_protocol_demo/captures/"
