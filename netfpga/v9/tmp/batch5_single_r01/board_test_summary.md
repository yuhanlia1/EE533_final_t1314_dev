# Board Test Summary

- run_name: `batch5_single_r01`
- bitfile: `nw_proc4_2_moreobserve.bit`
- result_mode: `compact_class_score`
- batch_alignment: `request_id`
- selected_samples: `5`

## Bypass Smoke

- `wrong_magic_bypass`: payload_magic=`0xbeef`, udp_dst_port=`0x88b5`
- `wrong_port_bypass`: payload_magic=`0xa11e`, udp_dst_port=`0x9999`

## Batch

- sample_count: `5`
- sent_count: `5`
- observed_count: `5`
- capture_count: `5`
- batch_capture_mode: `time_window`
- sender_capture_count: `5`
- receiver_capture_count: `5`
- class_matches: `5`
- wire_matches: `5`
- missing_samples: `0`
- missing_request_ids: `-`
- mismatches: `0`
- debug_emit_count: `5`
- engine_emit_count: `5`
- capture_vs_emit_gap: `0`
- pipeline_verdict: `healthy`
- expected_request_ids: `0x1334,0x1335,0x1336,0x1337,0x1338`
- sender_request_ids: `0x1334,0x1335,0x1336,0x1337,0x1338`
- receiver_request_ids: `0x1334,0x1335,0x1336,0x1337,0x1338`
- engine_last_emit_request_id: `0x1338`

## Debug Snapshot

```text
offload_accept_count   = 5
frame_hold_count       = 5
compute_start_count    = 5
compute_done_count     = 5
result_emit_count      = 5
last_parse_request_id  = 0x1338
last_compute_request_id = 0x1338
last_emit_request_id   = 0x1338
flags_raw              = 0x00000000
ingress_overflow_seen  = 0
parse_nonfatal_seen    = 0
parse_fatal_seen       = 0
emit_stall_seen        = 0
```
