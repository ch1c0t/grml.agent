# grml.agent

A Crystal application that boots a GRML live system in QEMU, provides a
host-side Tmux REPL for guest operations, and prepares verified offline
Alpine APK repository bundles.

## Build

bundle install
shards install
bundle exec rake

## Boot package profiles

The optional profile argument to `grml.agent boot` selects a package list
from the QEMU shared directory. For example, create
`shared/profiles/development/packages.txt` on the host:

```text
# Tools for a development environment
git
vim
tmux
build-essential
```

Then boot with:

```sh
./bin/grml.agent boot development
```

Before installing a non-empty profile, the guest automatically prepares the
shared Debian package cache using apt-cacher-ng. It then refreshes APT
metadata through the proxy and installs the listed packages with
`--no-install-recommends`. Preparation progress and APT output are streamed
to the terminal. The first preparation may install apt-cacher-ng itself and
therefore needs upstream network access unless apt-cacher-ng is already in
the GRML image. Later boots reuse package archives stored under
`shared/deb-cache/proxy`.

Each non-empty, non-comment line must be a Debian package name. If the
profile's `packages.txt` file is missing or contains an invalid package
entry, boot fails. An empty package list skips installation; with `--verify-deb-cache`, the
cache is still prepared and checked. Without a profile argument, boot does
not prepare the cache or install additional packages.

After the guest is running, apply a profile from the host-side REPL without
rebooting:

```text
apply_profile development
```

Profile application is additive: it installs or updates the listed packages,
but does not uninstall packages omitted from the selected profile. Applying
another profile therefore does not undo packages installed by an earlier one.
The optional ISO argument can be combined with a profile:
`./bin/grml.agent boot development --iso ./cdrom/grml.iso`.

Use `--verify-deb-cache` to run the separate offline cache check after the
profile packages have been installed:

```sh
./bin/grml.agent boot development --verify-deb-cache
```

This check downloads the current `hello` package through apt-cacher-ng,
temporarily disables upstream access, and confirms that the same archive
can be fetched again with a matching SHA-256 checksum. It is deliberately
opt-in: it performs an additional online/offline test and may fail for
repositories whose package payloads are not served over HTTP.

## Commands

./bin/grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]
./bin/grml.agent tmux [--iso PATH]
./bin/grml.agent prepare_alpine_bundle [alpine_branch]

grml.agent tmux starts tmux inside the guest and a separate host-side
Tmux REPL attached to the same running VM. The host REPL provides:

- ocr — recognize text in the latest guest display frame.
- guest_exec <shell command> — execute a shell command inside GRML through
  QEMU Guest Agent and stream stdout/stderr to the host REPL while it runs.
  The command runs as root in the guest. Quote a complete command string when
  it contains spaces or shell operators.
- create_disk <name> <size> [qcow2|raw] — create an image under ./disks/
  and hot-attach it as a virtio block device.
- attach_disk <path> [qcow2|raw] — hot-attach an existing image.
- create_ext4_disk <name> <size> [mountpoint] [qcow2|raw] — create a
  disk image on the host, hot-attach it, create a GPT partition in GRML,
  format that partition as ext4, and mount it in the guest. The default
  guest mount point is /mnt/<name>.
- prepare_alpine_bundle [alpine_branch] — create and verify an offline
  Alpine APK repository bundle.
- apply_profile <PROFILE_NAME> — install or update Debian packages listed
  in `shared/profiles/PROFILE_NAME/packages.txt` in the running guest. This
  is additive and does not remove packages from other profiles.
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

Long-running guest commands stream their output to the host REPL instead
of waiting for process exit. This includes `guest_exec`, Debian cache setup
and verification, and Alpine offline bundle downloads and verification.
Progress-stage messages are kept separate from the command's stdout/stderr.
Short guest commands continue to use the synchronous QEMU API.

The Debian package cache uses apt-cacher-ng at 127.0.0.1:3142 and stores
the proxy's cached repository data under /mnt/shared/deb-cache/proxy.
The setup installs apt-cacher-ng when it is missing, so that first
installation requires network access unless apt-cacher-ng is already in
the GRML image. Add apt-cacher-ng to the custom image's package selection
to have the service available on later boots. Run prepare_deb_cache again
to start the service and check its configuration after each boot. Run
verify_deb_cache [package] to demonstrate that the same package archive can
be fetched while upstream access is disabled; the default package is hello.
The setup configures APT's HTTP proxy and exports APT_PROXY for grml-live;
source /etc/profile.d/90-grml-agent-deb-cache.sh in an already-open shell.

APT still refreshes repository metadata to learn which package version is
current. When the requested .deb for that version is already cached,
apt-cacher-ng serves it locally. A newer package version has a different
repository path and is downloaded once; the cache does not force an older
version onto the build. See docs/deb-package-cache.md for details.

Set GRML_AGENT_REPL_FOCUS=false to keep the host tmux client in its current
session and switch manually with: tmux switch-client -t grml. Use
XEPHYR_LOG_LEVEL=DEBUG or TRACE for diagnostics.
