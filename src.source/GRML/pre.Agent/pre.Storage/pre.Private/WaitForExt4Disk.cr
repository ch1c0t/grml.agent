private def wait_for_ext4_disk : String
  <<-SCRIPT
    echo "Waiting for guest disk device: $disk"
    for attempt in $(seq 1 50); do
      [ -b "$disk" ] && break
      sleep 0.1
    done
    if [ ! -b "$disk" ]; then
      echo "Guest block device did not appear: $disk" >&2
      exit 1
    fi
  SCRIPT
end
