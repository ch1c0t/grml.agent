## Other REPL commands

grml.agent tmux starts tmux inside the guest and a separate host-side
Tmux REPL attached to the same running VM. The host REPL provides:

- ocr — recognize text in the latest guest display frame.
- guest_exec <shell command> — execute a shell command inside GRML through
  QEMU Guest Agent and stream stdout/stderr to the host REPL while it runs.
  The command runs as root in the guest. Quote a complete command string when
  it contains spaces or shell operators.
- copy_executable <host_path> <guest_path> — copy a host executable into the
  guest through the shared directory, creating destination directories and
  setting guest permissions to 0755. The guest path must be absolute.
- create_disk <name> <size> [qcow2|raw] — create an image under ./disks/
  and hot-attach it as a virtio block device.
- attach_disk <path> [qcow2|raw] — hot-attach an existing image.
- create_ext4_disk <name> <size> [mountpoint] [qcow2|raw] — create a
  disk image on the host, hot-attach it, create a GPT partition in GRML,
  format that partition as ext4, and mount it in the guest.
- prepare_alpine_bundle [alpine_branch] — create and verify an offline
  Alpine APK repository bundle.
- prepare_deb_cache — configure apt-cacher-ng to cache Debian package
  downloads under /mnt/shared/deb-cache.
- verify_deb_cache [package] — disable upstream access temporarily and
  verify that the same Debian package version can be fetched from the cache.

Each REPL command is implemented in its own module under
src.source/GRML/REPL/Commands/. The registered command names are also
the source of truth for input autocomplete; custom REPL sessions suggest
registered application commands instead of executables from the host PATH.

The create_ext4_disk command runs host-side image creation and QMP
hot-plugging, followed by guest-side GPT partitioning, ext4 formatting, and
mounting through QEMU Guest Agent. It identifies the added virtio device by
its serial, so it does not rely on a hard-coded /dev/vdb name. If guest
provisioning fails after attachment, the image is retained under ./disks/
and the attached device is left available for recovery.
