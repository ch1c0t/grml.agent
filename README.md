# grml.agent

A Crystal application that boots a GRML live system in QEMU, provides a
host-side Tmux REPL for guest operations, builds custom GRML live ISOs with
grml-live, and prepares verified offline Alpine APK repository bundles.

## Build

bundle install
shards install
bundle exec rake

## Boot package profiles

The optional profile argument to grml.agent boot selects a package list
from the QEMU shared directory. For example, create
shared/profiles/development/packages.txt on the host:

~~~text
# Extra packages installed into the running GRML guest
git
vim
tmux
build-essential
~~~

Then boot with:

~~~sh
./bin/grml.agent boot development
~~~

Before installing a non-empty profile, the guest automatically prepares the
shared Debian package cache using apt-cacher-ng. It then refreshes APT
metadata through the proxy and installs the listed packages with
--no-install-recommends. Preparation progress and APT output are streamed
to the terminal. The first preparation may install apt-cacher-ng itself and
therefore needs upstream network access unless apt-cacher-ng is already in
the GRML image. Later boots reuse package archives stored under
shared/deb-cache/proxy.

Each non-empty, non-comment line must be a Debian package name. If the
profile's packages.txt file is missing or contains an invalid package
entry, boot fails. An empty package list skips installation; with
--verify-deb-cache, the cache is still prepared and checked. Without a
profile argument, boot does not prepare the cache or install additional
packages.

After the guest is running, apply the same package list from the host-side
REPL without rebooting:

~~~text
apply_profile development
~~~

Profile application is additive: it installs or updates the listed packages,
but does not uninstall packages omitted from the selected profile. Applying
another profile therefore does not undo packages installed by an earlier one.
The optional ISO argument can be combined with a profile:
./bin/grml.agent boot development --iso ./cdrom/grml.iso.

Use --verify-deb-cache to run the separate offline cache check after the
profile packages have been installed:

~~~sh
./bin/grml.agent boot development --verify-deb-cache
~~~

This check downloads the current hello package through apt-cacher-ng,
temporarily disables upstream access, and confirms that the same archive
can be fetched again with a matching SHA-256 checksum. It is deliberately
opt-in: it performs an additional online/offline test and may fail for
repositories whose package payloads are not served over HTTP.

## Build custom ISOs with grml-live

A profile can also describe a complete grml-live build. The profile keeps
builder dependencies, ISO package selection, and system customization in
separate places:

~~~text
shared/profiles/rescue/
├── packages.txt                 # optional packages for the running GRML guest
├── builder-packages.txt         # optional extra packages for the build environment
└── grml-live/
    ├── build.yml                # grml-live command-line settings
    ├── config/                  # overlays merged over upstream grml-live/config
    │   ├── bootstrap-keyring/    # optional per-class mmdebstrap signing keys
    │   ├── package_config/
    │   │   └── RESCUE            # packages installed into the resulting ISO
    │   ├── debconf/
    │   ├── env/
    │   ├── files/
    │   ├── hooks/
    │   ├── scripts/
    │   ├── media-files/
    │   ├── media-scripts/
    │   ├── tools/
    │   └── grml/                  # global grml-live configuration
    └── chroot-install/           # optional files installed under / in the chroot
~~~

The directories under grml-live/config/ use the class-based configuration
format expected by grml-live. For each selected custom class, add one or more
definitions under the corresponding configuration directories. For example,
package_config/RESCUE defines software installed inside the ISO;
bootstrap-keyring/DEBIAN_TRIXIE can override the Debian suite keyring used by mmdebstrap;
scripts, hooks, debconf preseeding, file overlays, and media customizations
can be provided by the other directories. The last matching class with a bootstrap-keyring file is selected by minifai,
so overriding the automatically selected suite keyring uses its exact class
name (for example, DEBIAN_TRIXIE). The grml/ directory holds global settings
such as squashfs exclusions. The profile configuration is merged
over the selected grml-live checkout's default configuration, so it does not
need to copy the upstream GRMLBASE or GRML_SMALL definitions. Filesystem
overlays preserve symbolic links, which can be useful for system configuration
and service enablement. Use only profile content you trust, especially scripts
and hooks.

Example grml-live/build.yml:

~~~yaml
suite: trixie
classes:
  - GRML_SMALL
  - NO_ONLINE
  - RESCUE

hostname: rescue-system
username: operator
distri_name: rescue
distri_info: Custom GRML rescue environment
grml_name: rescue
release_name: rescue
version: "0.1.0"
iso_name: rescue_0.1.0.iso

boot_options:
  - ssh

secure_boot: false
release: false
bootstrap_mirror_url: http://deb.debian.org/debian

# Optional Debian snapshot date (YYYYMMDD or YYYYMMDDTHHMMSSZ).
# This applies to the plain Debian repositories used for bootstrap.
# wayback_date: "20261101"

# Pin a commit SHA for repeatable source selection; master follows upstream.
grml_live_ref: master

# Optional Unix timestamp for SOURCE_DATE_EPOCH.
# source_date_epoch: 1794950400
~~~

The classes list contains additional classes. grml-live automatically
adds its base, Debian-suite, architecture, and (unless release: false)
release classes. Do not list automatically selected classes such as
GRMLBASE, RELEASE, SECURE_BOOT, AMD64, ARM64, or DEBIAN_* yourself. Use
secure_boot: true to enable Secure Boot.

The package lists have deliberately different meanings:

- packages.txt is for packages installed into the currently running GRML
  guest by boot PROFILE or apply_profile PROFILE.
- builder-packages.txt adds Debian packages to the GRML guest that runs
  grml-live. The command also installs grml-live's required tools, Python
  YAML support, and user-namespace utilities.
- grml-live/config/package_config/CLASS determines packages installed
  into the live ISO. Use the grml-live PACKAGES install syntax there.

Prepare and validate a profile, then build it from the host REPL:

~~~text
prepare_build_environment rescue
validate_profile rescue
build_iso rescue
~~~

Preparation configures apt-cacher-ng, installs the build dependencies,
creates a dedicated unprivileged grml-live-builder account with subordinate
UID/GID ranges, checks user namespaces, and checks out the requested
grml-live ref. Modern grml-live must not run as root. Validation checks the
YAML manifest, package names, custom class definitions, and profile tree
before starting a build.

The build combines the checked-out upstream grml-live/config with the
profile's configuration overrides and runs grml-live image-create as the
unprivileged builder. Preparation creates or reuses a sparse 32 GiB qcow2
disk at ./disks/grml-live-build.qcow2 on the host and mounts its ext4
filesystem at /mnt/grml-live-build in the guest. The disk persists across
guest reboots and build runs. An existing ext4 filesystem is reused; an
unexpected filesystem is never reformatted. The stage directory, chroot,
temporary files, and grml-live output all live on this guest-local ext4
filesystem rather than the root filesystem or the QEMU shared directory.
Completed artifacts and logs are copied to the shared directory:

~~~text
shared/grml-live/runs/rescue/RUN_ID/
├── build.yml
├── COMPLETE                 # or FAILED
└── output/
    ├── grml_isos/
    └── grml_logs/
~~~

The build command verifies that /mnt/grml-live-build is a dedicated ext4
mount with sufficient free space and without nodev, noexec, or nosuid mount
options. A successful build must produce at least one ISO. The grml-live
commit used for the build and its exit status are recorded alongside the
artifacts. Pin grml_live_ref to a commit SHA, set wayback_date to a
Debian snapshot, and set source_date_epoch when repeatable source and
timestamp selection matters. wayback_date applies to the plain Debian
repositories used for bootstrap; it does not pin Grml or custom repositories.
Selecting NO_ONLINE disables certain network-dependent build scripts; it does
not make package downloads offline by itself.

Profiles contain executable build scripts and hooks that run inside the
grml-live build process. Only build profiles and configuration you trust
should be used.

## Other REPL commands

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

When --iso is omitted, GRML ISO discovery uses ./cdrom/ when that
directory exists; otherwise it uses ~/Downloads/ISOs/. Set QEMU_ISO_DIR
to choose a different discovery directory.

## Shared Debian package cache

The Debian package cache uses apt-cacher-ng at 127.0.0.1:3142 and stores
the proxy's cached repository data under /mnt/shared/deb-cache/proxy.
The setup installs apt-cacher-ng when it is missing, so that first
installation requires network access unless apt-cacher-ng is already in
the GRML image. Add apt-cacher-ng to the custom image's package selection
to have the service available on later boots. Run prepare_deb_cache again
to start the service and check its configuration after each boot. Run
verify_deb_cache [package] to demonstrate that the same package archive
can be fetched while upstream access is disabled; the default package is
hello. The setup configures APT's HTTP proxy and exports APT_PROXY
for grml-live.

APT still refreshes repository metadata to learn which package version is
current. When the requested .deb for that version is already cached,
apt-cacher-ng serves it locally. A newer package version has a different
repository path and is downloaded once; the cache does not force an older
version onto the build. See docs/deb-package-cache.md for details.

Set GRML_AGENT_REPL_FOCUS=false to keep the host tmux client in its current
session and switch manually with: tmux switch-client -t grml. Use
XEPHYR_LOG_LEVEL=DEBUG or TRACE for diagnostics.
