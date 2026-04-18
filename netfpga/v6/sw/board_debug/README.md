# Board CPU Debug Test

This directory contains the concrete board-side artifacts for validating the
CPU debug path after the `hw_reserved_0/1` readback fix.

## Files

- `send_ann_offload.py`
  Builds a valid ANN offload Ethernet frame. By default it only prints the
  generated packet metadata and wire hex. With `--send --iface <ifname>` it
  sends the frame through a raw AF_PACKET socket.
- `recv_ann_result.py`
  Captures ANN result frames on a raw Ethernet interface and prints decoded
  JSON rows.
- `run_ann_model_batch.py`
  Replays a whole `annmodelctl` test vector set, captures result frames, and
  compares them against the generated expected outputs.

## Recommended board test flow

For the USC lab machines, assume:

- local build host: runs `python3 sw/cpuctl`, `python3 sw/gpuctl`, `python3 sw/annmodelctl`
- remote `netfpga`: runs `perl sw/annctl`
- remote `node0-3`: runs `python sw/board_debug/...` on the lab's old `Python 2.4.3`

### 1. Program the CPU signature test

```bash
python3 sw/cpuctl build sw/testdata/board_cpu_signature.s --out-dir /tmp/board_cpu_signature
# scp /tmp/board_cpu_signature/image.txt to the remote netfpga host, then:
perl sw/annctl cpu load /tmp/board_cpu_signature/image.txt
```

This program writes the following low-32-bit signatures into CPU DMEM:

- `DMEM[0] = 0x000000a5`
- `DMEM[1] = 0x0000005a`
- `DMEM[2] = 0x0000003c`

Then it loops forever.

### 2. Satisfy engine readiness

Any GPU IMEM/parameter image that sets the programmed bits is sufficient for
this narrow CPU debug test. If no real ANN program is ready yet, use:

```bash
perl sw/annctl gpu imem-load sw/testdata/gpu_imem_sample.txt
perl sw/annctl gpu param-load sw/testdata/gpu_params_sample.txt
perl sw/annctl engine enable
perl sw/annctl engine status
```

Expected state before the packet trigger:

- `cpu_programmed = 1`
- `gpu_programmed = 1`
- `param_programmed = 1`
- `engine_ready = 1`

### 3. Verify CPU IMEM hardware readback

`hw_reserved_0` now exposes the CPU IMEM read port through `annctl`.

```bash
perl sw/annctl cpu hw-imem-dump 0 4
```

Compare the returned words against:

```bash
sed -n '1,4p' /tmp/board_cpu_signature/compiled_binary.txt
```

Expected outcome:

- each returned `cpu_hw_imem[...]` word matches the compiled binary at the same address

### 4. Send one valid ANN offload frame

The sender builds a raw Ethernet frame matching the current RTL/TB ANN
protocol:

- destination MAC: `0b:ad:c0:de:00:01`
- source MAC: `f0:0d:ca:fe:00:02`
- EtherType: `0x88b5`
- task magic: `0xa11e`
- request ID: `0x1234`
- feature count: `8`
- task type: `0x0000`

Dry-run first:

```bash
python sw/board_debug/send_ann_offload.py --dump-json
```

For model-driven board tests, you can now override the feature payload with an
explicit vector instead of the default seed pattern:

```bash
python sw/board_debug/send_ann_offload.py \
  --dump-json \
  --feature-values "3,2,1,1,2,0,1,0"
```

If you want the printed `expected_module_header` to match a different host
port setup during bring-up, override the metadata-only fields:

```bash
python sw/board_debug/send_ann_offload.py \
  --dump-json \
  --src-port 0x0001 \
  --dst-port-mask 0x0008
```

Then send:

```bash
sudo python sw/board_debug/send_ann_offload.py --send --iface <your_host_ifname>
```

If you are using the model bundle flow, build the sample multi-layer MLP first:

```bash
python3 sw/annmodelctl build sw/testdata/ann_model_mlp_int16.json --out-dir /tmp/ann_model_bundle
```

Then take one input vector from `/tmp/ann_model_bundle/test_vectors.json` and
feed it to `--feature-values` for a board-side classification smoke.

For batch board evaluation of an entire exported bundle:

```bash
sudo python sw/board_debug/run_ann_model_batch.py \
  --iface <your_host_ifname> \
  --test-vectors /tmp/ann_model_bundle/test_vectors.json \
  --expected /tmp/ann_model_bundle/expected_outputs.json \
  --observed-out /tmp/ann_model_bundle/observed_results.json \
  --report-out /tmp/ann_model_bundle/board_eval_report.json
```

This is the recommended path for the current binary-MNIST flow under
`sw/testdata/mnist_binary_01/`.

### 5. Verify CPU executed by reading DMEM signatures

`hw_reserved_1` exposes the low 32 bits of the CPU DMEM read port.

```bash
perl sw/annctl cpu hw-dmem-dump 0 3
```

Expected outcome after the packet trigger:

- `cpu_hw_dmem_low32[0x00000000] = 0x000000a5`
- `cpu_hw_dmem_low32[0x00000001] = 0x0000005a`
- `cpu_hw_dmem_low32[0x00000002] = 0x0000003c`

## Failure localization

- Programmed bits wrong:
  CPU/GPU/parameter load path is not correct yet.
- IMEM readback wrong but programmed bits are correct:
  CPU IMEM debug readback path or `sw_i_mem_addr[30]` selection is broken.
- IMEM readback correct but DMEM signatures never appear after packet send:
  CPU was not triggered, or CPU execution/store path is still wrong.
- DMEM signatures appear:
  `reg_req -> CPU IMEM -> CPU execution -> CPU DMEM -> hw_reserved_1` is closed on board.
