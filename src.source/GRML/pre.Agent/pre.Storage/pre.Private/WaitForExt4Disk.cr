private def wait_for_ext4_disk : String
  <<-SCRIPT
    echo "Waiting for guest disk with serial: $serial"
    for attempt in $(seq 1 50); do
      if [ ! -b "$disk" ]; then
        for serial_file in /sys/block/vd*/serial; do
          [ -r "$serial_file" ] || continue
          actual_serial=$(cat "$serial_file")
          if [ "$actual_serial" = "$serial" ]; then
            device="${serial_file#/sys/block/}"
            disk="/dev/${device%%/*}"
            echo "Found virtio disk by sysfs serial: $disk"
            break
          fi
        done
      fi
      [ -b "$disk" ] && break
      sleep 0.1
    done
    if [ ! -b "$disk" ]; then
      echo "Guest block device did not appear for serial: $serial" >&2
      report_missing_ext4_disk >&2
      exit 1
    fi
    case "$disk" in
      /dev/disk/by-id/*) partition="$disk-part1" ;;
      *) partition="${disk}1" ;;
    esac
    echo "Using guest disk: $disk; partition: $partition"
  SCRIPT
end
