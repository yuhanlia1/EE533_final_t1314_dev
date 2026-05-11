# Zero-Copy Limit Point Demo

- run_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_zero_copy_demo`
- runner_log: `logs/zero_copy_limit.log`
- zero_copy_verdict: `UNSTABLE`
- window_ms: `1`
- measurement_resolution_ms: `5`
- request_id: `0x1100`
- predicted_label: `Slow`
- receiver_completed_within_window: `False`
- inference_check: `WINDOW BELOW MEASUREMENT RESOLUTION`
- note: This window is not treated as a demo-grade pass result.

## Request Packet

- frame_kind: `ann_task`
- request_id: `0x1100`
- payload_magic: `0xa11e`
- udp_dst_port: `0x88b5`
- payload_len: `48`

```text
request_wire_hex=004e46324300a0369f0a5d5b08004500004c123440004011f2670a0010030a001203400188b500380000a11e110000140000ff9e00af00af006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```

## Observed Result

- frame_kind: `ann_result`
- request_id: `0x1100`
- udp_dst_port: `0x88b5`
- wire_result_data_0: `0x0001`
- wire_result_data_1: `0x014b`
- predicted_class: `1`
- predicted_score_s16: `331`

```text
observed_wire_hex=a0369f0a0eb1004e4632430208004500004c123440003f11f3670a0010030a001203400188b500380000a11f01001100000200040001014b006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```

