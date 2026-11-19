# Host-side REPL and runtime configuration

The GRML agent uses a host-side Tmux REPL to operate the QEMU guest through
the QEMU Guest Agent, the QEMU shared directory, and QMP disk hot-plugging.

## Start the guest and REPL

```sh
./bin/grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]
./bin/grml.agent tmux [--iso PATH]
```

`boot` starts GRML, verifies that the guest shell and QEMU Guest Agent are
ready, configures the console font, verifies the shared directory, optionally
applies a package profile, and starts the host REPL. `tmux` also types
`tmux` into the guest shell and starts the host REPL alongside it.

The QEMU shared directory is mounted in the guest at `/mnt/shared` using
virtio 9p. The agent verifies both host-to-guest reads and guest-to-host
writes before relying on it for file transfer or artifacts. The host-side
directory is `./shared/` when that directory exists in the launch directory;
otherwise the QEMU library defaults to `$HOME/shared/`.

QEMU Guest Agent execution uses the guest agent's command interface. In the
standard GRML configuration these commands run as root. The boot workflow
checks the guest agent before starting the host REPL.

## Commands

The following commands are registered in the host REPL:

| Command | Purpose |
| --- | --- |
| `ocr` | Recognize text in the latest guest display frame. |
| `guest_exec <shell command>` | Execute a shell command in the guest and stream stdout/stderr to the host REPL. |
| `copy_executable <host_path> <guest_path>` | Copy a host executable to an absolute guest path and install it with mode `0755`. |
| `apply_profile <name>` | Apply a guest package profile without rebooting. |
| `prepare_deb_cache` | Prepare apt-cacher-ng and the shared Debian package cache. |
| `verify_deb_cache [package]` | Verify that the same HTTP-served package archive can be fetched with upstream access disabled. |
| `prepare_build_environment <profile>` | Prepare the grml-live builder, dependencies, checkout, and persistent workspace. |
| `validate_profile <profile>` | Validate a grml-live profile and its class definitions. |
| `build_iso <profile>` | Build a custom GRML live ISO and preserve its artifacts. |
| `prepare_alpine_bundle [branch]` | Create and verify an Alpine offline APK dependency bundle. |
| `create_disk <name> <size> [qcow2\|raw]` | Create an image under `./disks/` and hot-attach it as a virtio disk. |
| `attach_disk <path> [qcow2\|raw]` | Hot-attach an existing disk image. |
| `create_ext4_disk <name> <size> [mountpoint] [qcow2\|raw]` | Create, attach, partition, format, and mount a new ext4 disk. |

Command names are registered from the application command modules and are
also the source of truth for input autocomplete. The REPL suggests registered
application commands rather than shell executables found on the host
`PATH`.

### Execute a guest command

For example:

```text
guest_exec id
```

The command runs in the guest through QEMU Guest Agent. Output is streamed
while the command runs; non-zero exit status is reported in the REPL.
Commands containing spaces or shell operators should be passed as a single
quoted command string.

### Copy a host executable

For example, to install the host's `mitamae` binary into the same path in
the guest:

```text
copy_executable /usr/local/bin/mitamae /usr/local/bin/mitamae
```

The agent verifies that the host source is a regular file and that the guest
destination is an absolute file path. It stages the bytes under a unique
temporary name in the shared directory, then runs guest-side
`install -D -m 0755` to create the destination directory and install the
executable. The temporary host-side file is removed after the operation,
including when guest installation fails. The installed mode is explicitly
`0755`; it does not attempt to preserve arbitrary source permissions.

### Create and attach disks

`create_disk` creates an image under the host's `./disks/` directory and
hot-attaches it. `attach_disk` hot-attaches an existing image.
`create_ext4_disk` creates a new image, attaches a virtio block device,
creates a GPT partition, formats it as ext4, and mounts it in the guest.
The guest device is located by its assigned virtio serial rather than by
assuming a fixed name such as `/dev/vdb`. If provisioning fails after
attachment, the image is retained on the host and the device remains
attached for recovery.

For the persistent grml-live build disk, see
[Custom GRML live ISO builds](grml-live-builds.md#persistent-build-workspace).
That workflow reuses an existing ext4 filesystem and refuses to format a
partition that contains another filesystem; this behavior is intentionally
different from creating a new ext4 disk.

## ISO discovery

The `--iso PATH` option selects a specific non-empty ISO file. When omitted,
the QEMU ISO resolver looks for a GRML ISO in:

1. `./cdrom/`, if that directory exists;
2. otherwise `~/Downloads/ISOs/`.

Set `QEMU_ISO_DIR` to use a different directory. Candidate filenames must
contain `grml` (case-insensitive) and end in `.iso`. If several candidates
exist, the first sorted filesystem glob result is selected and the ambiguity
is logged at DEBUG level. Passing `--iso` bypasses directory discovery.

## Tmux session focus and diagnostics

By default, the host REPL focuses the tmux session named `grml`. Set
`GRML_AGENT_REPL_FOCUS=false` to leave the current host tmux client in its
current session and switch manually:

```sh
tmux switch-client -t grml
```

The focus setting accepts common true and false values (`true`, `false`,
`yes`, `no`, `on`, `off`, `1`, and `0`). The default is true.

Set `XEPHYR_LOG_LEVEL=DEBUG` or `XEPHYR_LOG_LEVEL=TRACE` to increase
diagnostics from the Xephyr display/context process.

Build-environment commands retain their command scripts and combined logs
inside the guest under
`/var/log/grml-agent/build-environment/<stage>.sh` and
`/var/log/grml-agent/build-environment/<stage>.log`. The build workflow also
streams long-running APT, Git, and storage output to the host REPL. See
[Custom GRML live ISO builds](grml-live-builds.md) for build-stage and
artifact details.

## Related guides

- [Boot package profiles](package-profiles.md)
- [Custom GRML live ISO builds](grml-live-builds.md)
- [Shared Debian package cache](deb-package-cache.md)
- [Alpine offline bundle](alpine-offline-bundle.md)
