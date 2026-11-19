# Custom GRML live ISO builds

A build profile describes a grml-live ISO independently of the packages
installed into the currently running GRML guest. The profile resides in the
QEMU shared directory under `profiles/<name>/`; the guest sees it under
`/mnt/shared/profiles/<name>/`.

## Profile layout

```text
shared/profiles/rescue/
├── profiles.txt                 # optional dependencies for boot/apply_profile
├── packages.txt                 # optional packages for the running GRML guest
├── builder-packages.txt         # optional extra build-environment packages
└── grml-live/
    ├── build.yml                # grml-live build settings
    ├── config/                  # overlays merged over upstream grml-live/config
    │   ├── bootstrap-keyring/    # per-class mmdebstrap signing keys
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
```

The `profiles.txt` file composes package profiles for `boot PROFILE` and
`apply_profile PROFILE`; it is not a grml-live build manifest and does not
change `validate_profile` or `build_iso`. See
[Boot package profiles](package-profiles.md#boot-with-a-profile) for its
syntax and application order.

The `grml-live/config/` directories use the class-based configuration format
expected by grml-live. For each custom class, add one or more definitions
under the appropriate configuration category. For example,
`package_config/RESCUE` defines packages included in the ISO. Hooks, scripts,
debconf preseeding, file overlays, media customizations, and tools can be
provided through their corresponding directories. The `grml/` directory
holds global settings such as squashfs exclusions.

The profile configuration is copied over the selected upstream
`grml-live/config/` checkout, so a profile normally needs only its overrides;
it does not need to duplicate upstream `GRMLBASE` or `GRML_SMALL`
definitions. File overlays are staged with archive-preserving copies, so
symbolic links are preserved.

For bootstrap keyrings, minifai selects the last matching class that has a
`bootstrap-keyring/<CLASS>` file. An automatically selected suite class such
as `DEBIAN_TRIXIE` can therefore be used as the keyring override filename
even though automatic classes must not be listed in the manifest's
`classes` field.

Profiles may contain executable scripts and hooks that run during the
grml-live build. Treat profile contents as executable code and use only
profiles you trust.

## Manifest

A minimal example of `grml-live/build.yml`:

```yaml
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
```

The manifest accepts these keys:

- `suite`, `classes`
- `hostname`, `username`, `distri_name`, `distri_info`, `grml_name`,
  `release_name`, `version`, `iso_name`
- `boot_options`, `secure_boot`, `release`, `bootstrap_mirror_url`
- `grml_live_ref`, `date`, `wayback_date`, `source_date_epoch`

Unknown keys are rejected. Defaults include suite `trixie`, class
`GRML_SMALL`, hostname and username `grml`, release enabled, Secure Boot
disabled, and `grml_live_ref: master`.

The `classes` list contains requested classes. grml-live adds its base,
Debian-suite, architecture, and (unless `release: false`) release classes.
Do not list automatically selected classes such as `GRMLBASE`, `RELEASE`,
`SECURE_BOOT`, `AMD64`, `ARM64`, `I386`, or `DEBIAN_*` yourself.
`secure_boot: true` enables Secure Boot. At least one requested class is
required, and class names must be unique uppercase tokens.

The optional `date` field uses `YYYY-MM-DD`. `wayback_date` uses
`YYYYMMDD` or `YYYYMMDDTHHMMSSZ`. `source_date_epoch` is a positive
Unix timestamp passed as `SOURCE_DATE_EPOCH`.

## Prepare, validate, and build

Run these commands in the host-side GRML REPL:

```text
prepare_build_environment rescue
validate_profile rescue
build_iso rescue
```

`validate_profile` checks the profile tree and required manifest,
parses and validates the YAML, checks builder package names, and confirms
that every requested custom class has at least one definition under the
supported class configuration directories.

`prepare_build_environment` reports six timed top-level stages:

1. Validate the build profile.
2. Prepare the shared Debian package cache.
3. Install grml-live build dependencies.
4. Create the unprivileged `grml-live-builder` account and subordinate
   UID/GID ranges, then verify user-namespace mappings.
5. Provision the persistent ext4 build workspace.
6. Check out the requested grml-live ref.

The fixed builder package set includes `ca-certificates`, `curl`,
`dosfstools`, `e2fsprogs`, `git`, `jo`, `mmdebstrap`, `moreutils`,
`mtools`, `python3`, `python3-yaml`, `rsync`, `socat`,
`squashfs-tools`, `uidmap`, `util-linux`, and `xorriso`. Packages in
`builder-packages.txt` are added to this set. Modern grml-live must not run
as root; the workflow uses the dedicated unprivileged builder and verifies
that user namespaces and subordinate ID mappings work.

The source checkout is kept at `/opt/grml-live`. The configured
`grml_live_ref` is fetched and checked out detached; the resolved commit
SHA is reported and recorded with the build.

## Persistent build workspace

Preparation creates or reuses a sparse 32 GiB qcow2 image on the host:

```text
./disks/grml-live-build.qcow2
```

The image is attached to QEMU and its ext4 partition is mounted in the guest
at `/mnt/grml-live-build`. The filesystem persists across guest reboots
and build runs. The guest disk is identified by its virtio serial
(`grml-live-build`), first through
`/dev/disk/by-id/virtio-grml-live-build` and then, if needed, by matching
`/sys/block/vd*/serial`. The host checks QMP attachment metadata by the
canonical backing-file path rather than assuming QEMU will retain a
particular autogenerated block-node name.

An existing ext4 filesystem is reused. A blank new partition is formatted
as ext4; if a partition already contains a different filesystem, provisioning
refuses to format it. A mounted workspace is also checked to ensure it is
the expected ext4 partition and not some other mount.

Before a build, the agent verifies that the workspace is a dedicated ext4
mount, that it is not mounted with `nodev`, `noexec`, or `nosuid`, and
that it has sufficient free space (at least 2 GiB, or 4 GiB when
`GRML_FULL` is selected). The staging directory, chroot, temporary files,
and grml-live output are placed on this guest-local filesystem, not on the
root filesystem or the QEMU shared directory.

## Build execution and artifacts

The agent merges the selected upstream grml-live configuration with the
profile overrides and runs `grml-live image-create` as
`grml-live-builder`. It sets `TMPDIR` to the workspace staging directory
and passes `APT_PROXY=http://127.0.0.1:3142` to the build. If supplied,
`source_date_epoch` becomes `SOURCE_DATE_EPOCH`. A profile
`chroot-install/` directory is staged as grml-live's install directory.

Every build receives a unique run ID. Its persistent result directory is:

```text
/mnt/shared/grml-live/runs/<PROFILE>/<RUN_ID>/
├── build.yml
├── BUILDING                 # while running
├── COMPLETE                 # after successful build
├── FAILED                   # after a failed build
└── output/
    ├── grml_isos/
    └── grml_logs/
```

Only the applicable status marker is present at the end. The completion or
failure marker records the profile, run ID, selected grml-live commit, and
exit code. The build output and manifest are copied to the shared directory.
Partial output is preserved when possible after a failure, and the temporary
staging directory is removed in the final cleanup path. A successful
grml-live exit is not enough by itself: the workflow also checks that at
least one `.iso` file exists in `output/grml_isos/`.

## Reproducibility and network limits

For repeatable source selection, set `grml_live_ref` to a commit SHA instead
of following a moving branch such as `master`. Set `wayback_date` to select
a Debian snapshot for the plain Debian repositories used for bootstrap, and
set `source_date_epoch` when a stable build timestamp is needed.
`wayback_date` does not pin Grml or custom repositories.

Selecting `NO_ONLINE` disables certain network-dependent build scripts; it
does not make package downloads offline by itself. The builder still needs
the package sources it uses, and the configured apt-cacher-ng proxy caches
HTTP repository downloads rather than HTTPS payloads. See
[Shared Debian package cache](deb-package-cache.md).

## Verification boundary

The project's CI build and specs check source generation, compilation, CLI
behavior, and unit/integration-facing command logic. They do not by themselves
prove that a newly produced ISO boots successfully on a target machine.
After changing a build profile or grml-live source ref, inspect the retained
artifacts and boot the resulting ISO as an end-to-end check.
