private def ext4_provisioning_command(serial : String, mountpoint : String) : String
  disk = shell_quote("/dev/disk/by-id/virtio-#{serial}")
  target = shell_quote(mountpoint)

  <<-SCRIPT
    set -eu
    disk=#{disk}
    partition="$disk-part1"
    mountpoint=#{target}

    for attempt in $(seq 1 50); do
      [ -b "$disk" ] && break
      sleep 0.1
    done
    if [ ! -b "$disk" ]; then
      echo "Guest block device did not appear: $disk" >&2
      exit 1
    fi

    if mountpoint -q "$mountpoint"; then
      echo "Guest mount point is already in use: $mountpoint" >&2
      exit 1
    fi

    printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
    blockdev --rereadpt "$disk"
    udevadm settle

    for attempt in $(seq 1 50); do
      [ -b "$partition" ] && break
      sleep 0.1
    done
    if [ ! -b "$partition" ]; then
      echo "Guest partition did not appear: $partition" >&2
      exit 1
    fi

    mkfs.ext4 -F "$partition"
    mkdir -p "$mountpoint"
    mount -t ext4 "$partition" "$mountpoint"
    findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
    printf 'Mounted %s on %s as ext4\\n' "$partition" "$mountpoint"
  SCRIPT
end
