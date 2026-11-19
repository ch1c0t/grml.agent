# grml.agent

A Crystal application for running GRML in QEMU, operating the guest through a
host-side Tmux REPL, preparing reusable Debian package caches, and building
custom GRML live ISOs with grml-live. It also creates verified offline Alpine
APK repository bundles.

## Build

```sh
bundle install
shards install
bundle exec rake
```

## Quick start

```sh
./bin/grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]
./bin/grml.agent tmux [--iso PATH]
```

The first command boots GRML and starts the host-side REPL. The second also
starts tmux inside the guest. ISO selection and profile behavior are covered
in the guides below.

## Documentation

- [Boot package profiles](docs/package-profiles.md) — packages installed into
  the running guest and the `boot PROFILE` / `apply_profile PROFILE` flows.
- [Custom grml-live builds](docs/grml-live-builds.md) — profile structure,
  manifest fields, class overlays, build dependencies, persistent workspace,
  and artifact retention.
- [Host-side REPL](docs/host-repl.md) — available commands, host/guest file
  transfer, disk operations, session behavior, and diagnostics.
- [Shared Debian package cache](docs/deb-package-cache.md) — apt-cacher-ng
  configuration, cache semantics, and offline reuse verification.
- [Alpine offline bundle](docs/alpine-offline-bundle.md) — package selection,
  signature checks, output layout, and verification limits.
- [Source layout](docs/source-layout.md) — BGEM composition and generated
  Crystal source.

Profiles and build hooks execute commands inside the guest or build chroot.
Use only profile content and configuration that you trust.
