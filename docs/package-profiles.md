# Boot package profiles

A package profile installs additional Debian packages into the currently
running GRML guest. Profiles live in the QEMU shared directory under
`profiles/`; the guest sees that directory at `/mnt/shared/profiles`.

## Create a profile

For example, create `shared/profiles/development/packages.txt` on the host:

```text
# Extra packages installed into the running GRML guest
git
vim
tmux
build-essential
```

Each non-empty, non-comment line must contain one Debian binary package name.
Names are validated before APT is invoked; whitespace around entries and
inline comments are ignored. Duplicate package names are removed. A missing
`packages.txt` or an invalid entry makes profile application fail.

## Boot with a profile

```sh
./bin/grml.agent boot development
```

The optional profile argument selects
`/mnt/shared/profiles/development/packages.txt`. After the GRML shell and
QEMU Guest Agent are ready, the agent verifies the shared directory and
applies the profile.

For a non-empty package list, the agent:

1. prepares the shared Debian package cache with `prepare_deb_cache`;
2. refreshes APT metadata through the configured proxy;
3. installs the listed packages with `--no-install-recommends`.

APT output and preparation progress are streamed to the terminal. The first
cache preparation can install apt-cacher-ng itself and therefore needs
upstream network access unless that package is already installed in the
guest. Later runs reuse package archives in the shared cache. See
[Shared Debian package cache](deb-package-cache.md).

An empty package list skips cache preparation and package installation by
default. When `--verify-deb-cache` is supplied, cache preparation and the
cache verification still run even if the package list is empty.

The CLI syntax is:

```text
grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]
```

`--verify-deb-cache` requires a profile name. It performs a separate
integration check after profile installation: the current `hello` package
version is downloaded through apt-cacher-ng, upstream access is disabled,
and the same archive must be fetched again with a matching SHA-256 checksum.
It is opt-in because it requires an additional online/offline test and may
not work for package payloads served only over HTTPS. A different package
can be selected with the REPL command `verify_deb_cache [package]`.

Without a profile argument, boot does not prepare the package cache or
install additional packages.

## Apply a profile without rebooting

After boot, use the host-side REPL:

```text
apply_profile development
```

Profile application is additive: it installs or updates the packages listed
in the selected profile, but does not uninstall packages omitted from it.
Applying a second profile therefore does not undo packages installed by an
earlier profile.

The optional ISO path can be combined with a profile:

```sh
./bin/grml.agent boot development --iso ./cdrom/grml.iso
```

For the ISO lookup rules when `--iso` is omitted, see
[Host-side REPL and runtime configuration](host-repl.md#iso-discovery).

## Install host executables

A profile can optionally contain `host-executables.txt`. Each entry names
a command to look up on the host and an HTTPS fallback URL:

```text
# host command, then fallback URL for a Linux guest binary
mitamae https://github.com/itamae-kitchen/mitamae/releases/latest/download/mitamae-x86_64-linux
```

When the profile is applied, the agent first searches the host's executable
`PATH`. When it finds the command, it copies that file to the guest.
Otherwise, it downloads the configured URL on the host with `curl`, then
copies the downloaded file. Both paths install the executable as
`/usr/local/bin/<command>` with mode `0755`. The fallback URL can point to
a moving release URL such as GitHub's `releases/latest/download` endpoint;
the version is resolved when the profile is applied. Host-side `curl` is
needed only when the command is not already available.

The host executable is copied as-is, so it must be compatible with the
guest's operating system and architecture. A fallback should likewise name
a Linux release asset for the guest architecture. Blank lines and comments
are ignored; each entry must contain exactly a command name and an HTTPS
URL. Duplicate command names are rejected. The file is optional, and profiles
without it retain their existing behavior.

## Keep package lists separate

A profile used for a custom ISO build may contain more than `packages.txt`.
The three package-selection locations serve different purposes:

- `packages.txt` is installed into the currently running GRML guest by
  `boot PROFILE` or `apply_profile PROFILE`.
- `builder-packages.txt` adds Debian packages to the GRML guest that runs
  grml-live. The build workflow also installs its fixed set of required tools.
- `grml-live/config/package_config/CLASS` selects packages installed into
  the resulting live ISO, using grml-live's `PACKAGES` configuration syntax.

See [Custom grml-live builds](grml-live-builds.md) for the complete profile
layout and build workflow.
