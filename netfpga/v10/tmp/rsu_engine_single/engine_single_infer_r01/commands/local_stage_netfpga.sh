#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_engine_single/engine_single_infer_r01"

ssh netfpga@nf9.usc.edu "mkdir -p /home/netfpga/scripts/v8/engine_single_infer_r01_netfpga /home/netfpga/scripts/v8/engine_single_infer_r01_results"
scp -r "$RUN_DIR/deploy_netfpga/." netfpga@nf9.usc.edu:/home/netfpga/scripts/v8/engine_single_infer_r01_netfpga/
scp -r "$RUN_DIR/bundle" netfpga@nf9.usc.edu:/home/netfpga/scripts/v8/engine_single_infer_r01_netfpga/bundle

ssh node4@nf5.usc.edu "mkdir -p ~/v8/engine_single_infer_r01_sender/pcaps ~/v8/engine_single_infer_r01_sender/captures"
scp -r "$RUN_DIR/pcaps/." node4@nf5.usc.edu:~/v8/engine_single_infer_r01_sender/pcaps/

ssh node4@nf7.usc.edu "mkdir -p ~/v8/engine_single_infer_r01_receiver/captures"
