# RSU Cuda-like Engine Demo

- overall_verdict: `PASS`
- request_id: `0x1100`
- predicted_class: `1`
- predicted_label: `Slow`
- predicted_score_s16: `331`
- inference_check: `MATCHED EXPECTED OFFLOAD RESULT`
- config_path: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/scripts/board/rsu_demo_single_infer.json`
- output_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_engine_single`

## Packets

- sent_packet: `request_id=0x1100 frame_kind=ann_task payload_magic=0xa11e udp_dst_port=0x88b5`
- received_packet: `request_id=0x1100 frame_kind=ann_result udp_dst_port=0x88b5 wire_result_data_0_u16=0x0001 wire_result_data_1_u16=0x014b predicted_class=1 predicted_score_s16=331`

```text
sent_wire_hex=004e46324300a0369f0a5d5b08004500004c123440004011f2670a0010030a001203400188b500380000a11e110000140000ff9e00af00af006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
received_wire_hex=a0369f0a0eb1004e4632430208004500004c123440003f11f3670a0010030a001203400188b500380000a11f01001100000200040001014b006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```

## Artifacts

- demo_summary_json: `demo_summary.json`
- demo_summary_md: `demo_summary.md`
- detailed_summary_json: `summary.json`
- detailed_summary_md: `summary.md`
