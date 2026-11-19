GRML_LIVE_CHECKOUT = "/opt/grml-live"
GRML_LIVE_BUILDER = "grml-live-builder"
GRML_LIVE_BUILD_DISK_NAME = "grml-live-build"
GRML_LIVE_BUILD_DISK_SIZE = "32G"
GRML_LIVE_BUILD_WORKSPACE = "/mnt/grml-live-build"
GRML_LIVE_BUILD_STAGE_ROOT = GRML_LIVE_BUILD_WORKSPACE + "/stage"
GRML_LIVE_BUILD_RUN_ROOT = "/mnt/shared/grml-live/runs"
GRML_LIVE_BUILDER_PACKAGES = %w(
  ca-certificates curl dosfstools e2fsprogs git jo mmdebstrap moreutils mtools
  python3 python3-yaml rsync socat squashfs-tools uidmap util-linux xorriso
)

include Public
include Private
