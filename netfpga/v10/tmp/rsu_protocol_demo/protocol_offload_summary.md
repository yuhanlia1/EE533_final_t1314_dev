# Accepted Compute

- step: `offload`
- status: `PASS`
- run_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_protocol_demo`
- runner_log: `logs/protocol_offload.log`
- expected_behavior: Replay a legal ANN task packet. The receiver should observe an ANN result frame with the expected class/score fields.
- protocol_check: Captured ann_result request_id=0x1100 predicted_class=1 predicted_score_s16=331

## Sent Packet

- frame_kind: `ann_task`
- request_id: `0x1100`
- payload_magic: `0xa11e`
- udp_dst_port: `0x88b5`
- payload_len: `48`

```text
sent_wire_hex=004e46324300a0369f1d48c308004500004c123440004011fa670a000c030a000e03400188b500380000a11e110000140000ff9e00af00af006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```

## Observed Packet

- frame_kind: `ann_result`
- request_id: `0x1100`
- udp_dst_port: `0x88b5`
- wire_result_data_0: `0x0001`
- wire_result_data_1: `0x014b`
- predicted_class: `1`
- predicted_score_s16: `331`

```text
observed_wire_hex=a0369f0a5c65004e4632430208004500004c123440003f11fb670a000c030a000e03400188b500380000a11f01001100000200040001014b006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```
