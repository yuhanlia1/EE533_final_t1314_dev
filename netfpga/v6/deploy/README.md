# Deploy Layout

This `deploy/` tree mirrors the roles needed for the USC NetFPGA 1G lab, but it
now separates the modern build host from the old remote lab machines.

## Roles

- `buildhost/`
  Local modern-Python workspace. Run `cpuctl`, `gpuctl`, and `annmodelctl`
  here to generate CPU/GPU/parameter artifacts and test vectors.
- `netfpga/`
  Remote control host package. On the USC lab machines, treat this as
  `annctl` + register map + prebuilt artifacts only.
- `node0/`
  Remote sender package. Use it to send ANN EtherType frames.
- `node2/`
  Remote receiver package. Use it to capture ANN result frames.

## Remote Compatibility

- `buildhost/` expects `python3 >= 3.9`
- `netfpga/annctl` is kept compatible with older lab Perl
- `node0/` and `node2/` runtime scripts are written in a Python 2.4 / 3.x
  compatible subset because the USC nodes do not reliably provide `python3`

## Suggested SCP Layout

- Local machine:
  - keep and run `deploy/buildhost/`
- NetFPGA control host:
  - upload `deploy/netfpga/*`
- Sender host:
  - upload `deploy/node0/*`
- Receiver host:
  - upload `deploy/node2/*`

## Typical Flow

1. On the local build host, run `deploy/buildhost/bin/annmodelctl build ...`
   or `cpuctl/gpuctl build ...`
2. Copy generated artifacts from `deploy/buildhost/artifacts/...` to the remote
   `netfpga/artifacts/...`
3. On the remote NetFPGA host, use `perl bin/annctl ...` to load CPU IMEM,
   GPU IMEM, and GPU params, then `engine enable`
4. On the receiver node, start `python bin/recv_ann_result.py ...`
5. On the sender node, run `python bin/send_ann_offload.py --send ...`

## Local Smoke Checks

From repo root:

```bash
perl deploy/netfpga/bin/annctl regs list
python3 deploy/buildhost/bin/cpuctl --help
python3 deploy/buildhost/bin/gpuctl --help
python3 deploy/buildhost/bin/annmodelctl --help
python deploy/node0/bin/send_ann_offload.py --dump-json
python deploy/node2/bin/recv_ann_result.py --help
```
