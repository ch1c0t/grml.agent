private def ensure_ext4_provisioning_command(serial : String, mountpoint : String) : String
  [
    "set -eu",
    "serial=#{shell_quote(serial)}",
    "disk=#{shell_quote("/dev/disk/by-id/virtio-#{serial}")}",
    "partition=\"\"",
    "mountpoint=#{shell_quote(mountpoint)}",
    wait_for_ext4_disk,
    verify_ext4_mount,
    create_ext4_partition,
    format_ext4_partition,
    mount_ext4_partition,
  ].join("\n")
end
