private def ensure_ext4_provisioning_command(serial : String, mountpoint : String) : String
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

    for attempt in $(seq 1 50); do
      [ -b "$partition" ] && break
      sleep 0.1
    done

    if mountpoint -q "$mountpoint"; then
      mounted_source=$(findmnt -n -o SOURCE --target "$mountpoint")
      mounted_type=$(findmnt -n -o FSTYPE --target "$mountpoint")
      if [ "$mounted_type" != ext4 ] || [ "$(readlink -f "$mounted_source")" != "$(readlink -f "$partition")" ]; then
        echo "Build workspace is already mounted from another filesystem: $mountpoint" >&2
        exit 1
      fi
      echo "Existing ext4 build workspace is already mounted at $mountpoint"
      exit 0
    fi

    mkdir -p "$mountpoint"

    if [ ! -b "$partition" ]; then
      partition_table=$(blkid -p -o value -s PTTYPE "$disk" 2>/dev/null || true)
      filesystem=$(blkid -p -o value -s TYPE "$disk" 2>/dev/null || true)
      if [ -n "$partition_table" ] || [ -n "$filesystem" ]; then
        echo "Existing build disk has signatures but no first partition; refusing to repartition it" >&2
        exit 1
      fi

      printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
      blockdev --rereadpt "$disk"
      udevadm settle
      for attempt in $(seq 1 50); do
        [ -b "$partition" ] && break
        sleep 0.1
      done
    fi

    if [ ! -b "$partition" ]; then
      echo "Build disk partition did not appear: $partition" >&2
      exit 1
    fi

    filesystem=$(blkid -p -o value -s TYPE "$partition" 2>/dev/null || true)
    if [ -z "$filesystem" ]; then
      mkfs.ext4 -F "$partition"
    elif [ "$filesystem" != ext4 ]; then
      echo "Existing build disk partition has filesystem '$filesystem', expected ext4; refusing to format it" >&2
      exit 1
    fi

    mount -t ext4 "$partition" "$mountpoint"
    findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
    printf 'Mounted existing build partition %s on %s as ext4\\n' "$partition" "$mountpoint"
  SCRIPT
end
