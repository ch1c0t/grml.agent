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
- the daemon to listen only on `127.0.0.1:3142` and expose its local
  status page;
- a write-permission check using the daemon's `apt-cacher-ng` service user
  before the service is restarted;
- a systemd service drop-in that allows writes to the shared cache and
  prevents the daemon from starting before `/mnt/shared` is mounted;
- APT's HTTP proxy as `http://127.0.0.1:3142`;
- the `APT_PROXY` environment variable used by grml-live's mmdebstrap
  bootstrap and the later chroot package installation.

The service drop-in is needed because Debian's apt-cacher-ng service
restricts its writable paths. The cache remains in the shared directory
when the GRML VM is shut down.

## Package version behavior

APT refreshes repository metadata to discover the current candidate version.
The package archive URL includes the package version. If that exact archive
is already in the apt-cacher-ng cache, the proxy serves the cached file
instead of downloading it again. When a newer version is selected, its
archive is fetched once and then retained in the cache.

This reuses package archives without pinning the build to stale package
versions. It does not make repository metadata immutable: a build still
needs updated repository indexes to discover current versions.

The proxy caches HTTP repository traffic. HTTPS repository traffic is not
cached by this HTTP proxy. GRML's standard Debian repository configuration
uses HTTP URLs; custom HTTPS repositories should be changed to HTTP where
appropriate or mirrored separately.

The proxy cache may contain multiple versions over time. Its data is kept
separate from other shared artifacts in `/mnt/shared/deb-cache/proxy`.

## Current shell and subsequent boots

The command writes APT's proxy configuration and exports `APT_PROXY` in
new login shells. An already-open shell does not automatically inherit new
environment variables; run:

```sh
. /etc/profile.d/90-grml-agent-deb-cache.sh
```

Run `prepare_deb_cache` after each GRML boot. It checks that the shared
directory is mounted, reloads systemd, starts the proxy with the shared
cache directory, and verifies that the proxy responds before reporting
success. The systemd condition also prevents the service from starting
against a missing shared mount.

For GRML ISO builds, make sure the shell which launches `grml-live` has
`APT_PROXY` in its environment. The APT configuration file also configures
ordinary APT commands to use the proxy automatically.

## Verify actual package reuse

prepare_deb_cache verifies the mount, daemon configuration, service-user write
access, and proxy readiness. It does not download a package, so its success
message must not be interpreted as proof that an archive has been cached.

Run:

    verify_deb_cache

The command uses the Debian package hello by default. You can select another
package with verify_deb_cache bash. The package name must be a simple Debian
binary package name.

The verification performs an integration test through APT:

1. Refresh package indexes and resolve the current candidate version.
2. Download that exact .deb through the configured APT HTTP proxy into a
   fresh temporary directory and record its SHA-256 checksum.
3. Temporarily configure apt-cacher-ng with Offlinemode: 1. In this mode the
   proxy refuses upstream downloads and can only serve content already in
   its cache.
4. Download the same package version again into a different temporary
   directory. The command compares its SHA-256 checksum with the first
   download.
5. Remove the temporary offline-mode configuration and restart apt-cacher-ng
   in normal online mode, including when a verification stage fails.

A successful result therefore demonstrates that the same package archive was
served while upstream access was disabled. The first download requires network
access unless the archive is already cached. The selected package must come
from an HTTP repository; this proxy does not cache HTTPS package payloads.
Temporary download files are removed after the test. The first successful
download remains in the persistent shared cache.
