# grml.agent

A Crystal application that boots a GRML live system in QEMU, provides a
host-side Tmux REPL for guest operations, and prepares verified offline
Alpine APK repository bundles.

## Build

```sh
bundle install
shards install
bundle exec rake
```

## Commands

```sh
./bin/grml.agent boot [--iso PATH]
./bin/grml.agent tmux [--iso PATH]
./bin/grml.agent prepare_alpine_bundle [alpine_branch]
```

`grml.agent tmux` starts tmux inside the guest and a separate host-side
Tmux REPL attached to the same running VM. The host REPL provides:

- `ocr` — recognize text in the latest guest display frame.
- `create_disk <name> <size> [qcow2|raw]` — create an image under
  `./disks/` and hot-attach it as a virtio block device.
- `attach_disk <path> [qcow2|raw]` — hot-attach an existing image.
- `prepare_alpine_bundle [alpine_branch]` — create and verify an offline
  Alpine APK repository bundle.

Example host REPL commands:

```text
create_disk data 20G
attach_disk ./disks/existing.qcow2
ocr
```

Hot-attached disks should appear as new block devices in GRML (for example,
`/dev/vdb`). Partitioning and formatting are intentionally separate guest
operations; adding a device does not automatically modify its contents.

When `--iso` is omitted, GRML ISO discovery uses `./cdrom/` when that
directory exists; otherwise it uses `~/Downloads/ISOs/`. Set `QEMU_ISO_DIR`
to choose a different discovery directory.

The offline-bundle workflow stores immutable runs beneath
`/mnt/shared/alpine-bundles/runs/`. See
[docs/alpine-offline-bundle.md](docs/alpine-offline-bundle.md) for details.

Set `GRML_AGENT_REPL_FOCUS=false` to keep the host tmux client in its current
session and switch manually with `tmux switch-client -t grml`. Use
`XEPHYR_LOG_LEVEL=DEBUG` or `TRACE` for diagnostics.
