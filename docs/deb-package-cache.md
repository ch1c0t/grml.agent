# Shared Debian package cache

The GRML guest can cache Debian repository downloads in the QEMU shared
directory by using apt-cacher-ng.

## Prepare

Boot GRML with the shared directory mounted at `/mnt/shared`, start the
host-side REPL, and run:

```text
prepare_deb_cache
```

If apt-cacher-ng is not already installed, the command installs it. This
initial installation requires network access. For repeatable offline use,
include `apt-cacher-ng` in the package selection of the custom GRML image
so the daemon is present after each boot.

The command configures:

- apt-cacher-ng's `CacheDir` as `/mnt/shared/deb-cache/proxy`;
- the daemon to listen only on `127.0.0.1:3142`;
- APT's HTTP proxy as `http://127.0.0.1:3142`;
- the `APT_PROXY` environment variable used by grml-live's mmdebstrap
  bootstrap and the later chroot package installation.

It also verifies that the daemon responds before reporting success. The
cache remains in the shared directory when the GRML VM is shut down.

## Package version behavior

APT refreshes repository metadata to discover the current candidate version.
The package archive URL includes the package version. If that exact archive
is already in the apt-cacher-ng cache, the proxy serves the cached file
instead of downloading it again. When a newer version is selected, its
archive is fetched once and then retained in the cache.

This reuses package archives without pinning the build to stale package
versions. It does not make repository metadata immutable: a build still
needs updated repository indexes to discover current versions.

The proxy cache may contain multiple versions over time. Its data is kept
separate from other shared artifacts in `/mnt/shared/deb-cache/proxy`.

## Current shell

The command persists `APT_PROXY` for future login shells and writes APT's
proxy configuration. An already-open shell does not automatically inherit
new environment variables; run:

```sh
. /etc/profile.d/90-grml-agent-deb-cache.sh
```

The cache setup is idempotent. Run `prepare_deb_cache` again after a GRML
boot to restart the proxy and verify that the shared cache is usable.
