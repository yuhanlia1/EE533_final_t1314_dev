#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v9/tmp/batch5_single_r01"

ssh netfpga@nf3.usc.edu "mkdir -p /home/netfpga/scripts/v8/batch5_single_r01_netfpga /home/netfpga/scripts/v8/batch5_single_r01_results"
scp -r "$RUN_DIR/deploy_netfpga/." netfpga@nf3.usc.edu:/home/netfpga/scripts/v8/batch5_single_r01_netfpga/
scp -r "$RUN_DIR/bundle" netfpga@nf3.usc.edu:/home/netfpga/scripts/v8/batch5_single_r01_netfpga/bundle

ssh node3@nf4.usc.edu "mkdir -p ~/v8/batch5_single_r01_sender/pcaps ~/v8/batch5_single_r01_sender/captures"
scp -r "$RUN_DIR/pcaps/." node3@nf4.usc.edu:~/v8/batch5_single_r01_sender/pcaps/

ssh node3@nf1.usc.edu "mkdir -p ~/v8/batch5_single_r01_receiver/captures"
