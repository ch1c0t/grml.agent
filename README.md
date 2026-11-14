# grml.agent

A Crystal application that boots a GRML live system in QEMU and exposes its
screen and guest operations through a tmux REPL. It also prepares verified
offline Alpine APK repository bundles.

## Requirements

- Crystal 1.22 or newer
- QEMU plus the `xephyr.run` and `xephyr.kill` executables provided by
  [xephyr.context](https://github.com/ch1c0t/xephyr.context)
- Tesseract OCR with English language data
- A running LavinMQ instance configured for
  [global-amqp_channel](https://github.com/ch1c0t/crystal.global-amqp_channel)
- tmux and the guest-side GRML utilities used by the boot workflow

The reusable VM and display interaction implementation is provided by
[ch1c0t/crystal.qemu](https://github.com/ch1c0t/crystal.qemu).

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

When `--iso` is omitted, GRML ISO discovery uses `./cdrom/` when that
directory exists; otherwise it uses `~/Downloads/ISOs/`. Set
`QEMU_ISO_DIR` to choose a different discovery directory.

- `boot` waits for the GRML shell, verifies QEMU Guest Agent command
  execution and the host/guest shared directory, configures the console, and
  starts the `grml` REPL.
- `tmux` boots GRML, starts the guest's tmux directly, and keeps the VM
  running until Ctrl-C.
- `prepare_alpine_bundle` runs the offline-bundle workflow in a temporary
  GRML VM, then terminates that VM.

The REPL provides `ocr` and `prepare_alpine_bundle [alpine_branch]`.
The latter stores immutable runs beneath
`/mnt/shared/alpine-bundles/runs/`, verifies APK signatures and the offline
installation, writes a manifest and checksums, and updates `LATEST` only
after all checks pass. See
[docs/alpine-offline-bundle.md](docs/alpine-offline-bundle.md) for the
artifact format and trust model.

Set `GRML_AGENT_REPL_FOCUS=false` to keep the current tmux client in the boot
pane and switch manually with `tmux switch-client -t grml`. Use
`XEPHYR_LOG_LEVEL=DEBUG` or `TRACE` for diagnostics.

## Scope

The `create_alpine_image` command from the original monorepo was an
unimplemented stub and is intentionally not exposed here. The custom Alpine
ISO workflow will be added when its upstream `mkimage`-based implementation
is ready.
