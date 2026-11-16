# grml.agent

A Crystal application that boots a GRML live system in QEMU, provides a
host-side Tmux REPL for guest operations, and prepares verified offline
Alpine APK repository bundles.

## Build

bundle install
shards install
bundle exec rake

## Commands

./bin/grml.agent boot [--iso PATH]
./bin/grml.agent tmux [--iso PATH]
./bin/grml.agent prepare_alpine_bundle [alpine_branch]

grml.agent tmux starts tmux inside the guest and a separate host-side
Tmux REPL attached to the same running VM. The host REPL provides:

- ocr — recognize text in the latest guest display frame.
- guest_exec <shell command> — execute a shell command inside GRML through
  QEMU Guest Agent and return its stdout/stderr to the host REPL. The command
  runs as root in the guest. Quote a complete command string when it contains
  spaces or shell operators.
- create_disk <name> <size> [qcow2|raw] — create an image under ./disks/
  and hot-attach it as a virtio block device.
- attach_disk <path> [qcow2|raw] — hot-attach an existing image.
- create_ext4_disk <name> <size> [mountpoint] [qcow2|raw] — create a
  disk image on the host, hot-attach it, create a GPT partition in GRML,
  format that partition as ext4, and mount it in the guest. The default
  guest mount point is /mnt/<name>.
- prepare_alpine_bundle [alpine_branch] — create and verify an offline
  Alpine APK repository bundle.
- prepare_deb_cache — configure apt-cacher-ng to cache Debian package
  downloads under /mnt/shared/deb-cache.
- verify_deb_cache [package] — disable upstream access temporarily and verify
  that the same Debian package version can be fetched from the shared cache.

Example host REPL commands:

    create_disk data 20G
    attach_disk ./disks/existing.qcow2
    create_ext4_disk workspace 8G
    create_ext4_disk data 20G /mnt/data raw
    prepare_deb_cache
    verify_deb_cache hello
    guest_exec 'lsblk -f; blkid -p /dev/vda1; file -s /dev/vda1'
    ocr

Each REPL command is implemented in its own module under
src.source/GRML/REPL/Commands/. GRML::REPL::Definition assembles those
modules into the Tmux REPL definition. The registered command names are also
the source of truth for input autocomplete; custom REPL sessions suggest
registered application commands instead of executables from the host PATH.

The create_ext4_disk command runs host-side image creation and QMP
hot-plugging, followed by guest-side GPT partitioning, ext4 formatting, and
mounting through QEMU Guest Agent. It identifies the added virtio device by
its serial, so it does not rely on a hard-coded /dev/vdb name. If guest
provisioning fails after attachment, the image is retained under ./disks/
and the attached device is left available for recovery.

When --iso is omitted, GRML ISO discovery uses ./cdrom/ when that
directory exists; otherwise it uses ~/Downloads/ISOs/. Set QEMU_ISO_DIR
to choose a different discovery directory.

The offline-bundle workflow stores immutable runs beneath
/mnt/shared/alpine-bundles/runs/. See
docs/alpine-offline-bundle.md for details.

The Debian package cache uses apt-cacher-ng at 127.0.0.1:3142 and stores
the proxy's cached repository data under /mnt/shared/deb-cache/proxy.
The setup installs apt-cacher-ng when it is missing, so that first
installation requires network access unless apt-cacher-ng is already in
the GRML image. Add apt-cacher-ng to the custom image's package selection
to have the service available on later boots. Run prepare_deb_cache again
to start the service and verify the cache after each boot. The command
configures APT's HTTP proxy and exports APT_PROXY for grml-live; source
/etc/profile.d/90-grml-agent-deb-cache.sh in an already-open shell.

APT still refreshes repository metadata to learn which package version is
current. When the requested .deb for that version is already cached,
apt-cacher-ng serves it locally. A newer package version has a different
repository path and is downloaded once; the cache does not force an older
version onto the build. See docs/deb-package-cache.md for details.

Set GRML_AGENT_REPL_FOCUS=false to keep the host tmux client in its current
session and switch manually with: tmux switch-client -t grml. Use
XEPHYR_LOG_LEVEL=DEBUG or TRACE for diagnostics.
