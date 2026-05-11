# Payload Gate

- step: `wrong_magic`
- status: `PASS`
- run_dir: `/home/reili/ee533/lab9/EE533_final_t1314_dev/netfpga/v10/tmp/rsu_protocol_demo`
- runner_log: `logs/protocol_wrong_magic.log`
- expected_behavior: Replay a packet on the ANN UDP port with an invalid payload magic. The receiver should capture it, but it must stay on the bypass path.
- protocol_check: Captured udp_unknown on udp_dst_port=0x88b5 with payload_magic=0xbeef; packet did not enter compute

## Sent Packet

- frame_kind: `udp_unknown`
- request_id: `0x1100`
- payload_magic: `0xbeef`
- udp_dst_port: `0x88b5`
- payload_len: `48`

```text
sent_wire_hex=004e46324300a0369f0a5d5b08004500004c123440004011f2670a0010030a001203400188b500380000beef110000140000ff9e00af00af006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```

## Observed Packet

- frame_kind: `udp_unknown`
- request_id: `0x1100`
- payload_magic: `0xbeef`
- udp_dst_port: `0x88b5`
- payload_len: `48`

```text
observed_wire_hex=a0369f0a0eb1004e4632430208004500004c123440003f11f3670a0010030a001203400188b500380000beef110000140000ff9e00af00af006200ca00b4ffb4ffa6ffcdffd000a3ffdaffe80019ff8affdcffdd015a00e40041
```
