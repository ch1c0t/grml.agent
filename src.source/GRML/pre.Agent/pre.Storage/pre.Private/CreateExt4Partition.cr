private def create_ext4_partition : String
  <<-SCRIPT
    if [ ! -b "$partition" ]; then
      partition_table=$(blkid -p -o value -s PTTYPE "$disk" 2>/dev/null || true)
      if [ -n "$partition_table" ]; then
        echo "Waiting for existing guest partition device"
        for attempt in $(seq 1 50); do
          [ -b "$partition" ] && break
          sleep 0.1
        done
      fi
      if [ ! -b "$partition" ]; then
        filesystem=$(blkid -p -o value -s TYPE "$disk" 2>/dev/null || true)
        if [ -n "$partition_table" ] || [ -n "$filesystem" ]; then
          echo "Disk has unexpected signatures; refusing to repartition" >&2
          exit 1
        fi
        echo "Creating GPT partition table and ext4 partition"
        printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
        blockdev --rereadpt "$disk"
        udevadm settle
        for attempt in $(seq 1 50); do
          [ -b "$partition" ] && break
          sleep 0.1
        done
      fi
    fi
    [ -b "$partition" ] || { echo "Partition did not appear: $partition" >&2; exit 1; }
  SCRIPT
end
