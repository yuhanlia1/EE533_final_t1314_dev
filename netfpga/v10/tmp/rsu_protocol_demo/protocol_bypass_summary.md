# Bypass Gate

- step: `bypass`
- status: `PASS`
- run_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_protocol_demo`
- runner_log: `logs/protocol_bypass.log`
- expected_behavior: Replay a normal IPv4/UDP packet on a non-ANN destination port. The receiver should capture it, but the ANN engine should ignore it.
- protocol_check: Captured udp_unknown on udp_dst_port=0x7777; packet stayed on bypass path

## Sent Packet

- frame_kind: `udp_unknown`
- request_id: `0x4d4f`
- payload_magic: `0x4445`
- udp_dst_port: `0x7777`
- payload_len: `11`

```text
sent_wire_hex=004e46324300a0369f0a5d5b080045000027123440004011f28c0a0010030a001203400177770013000044454d4f5f425950415353
```

## Observed Packet

- frame_kind: `udp_unknown`
- request_id: `0x4d4f`
- payload_magic: `0x4445`
- udp_dst_port: `0x7777`
- payload_len: `11`

```text
observed_wire_hex=a0369f0a0eb1004e46324302080045000027123440003f11f38c0a0010030a001203400177770013000044454d4f5f42595041535300000000000000
```
