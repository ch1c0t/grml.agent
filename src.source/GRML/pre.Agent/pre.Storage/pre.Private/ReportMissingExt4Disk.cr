private def report_missing_ext4_disk : String
  <<-SCRIPT
    echo "Guest block devices:"
    lsblk -o NAME,PATH,TYPE,SIZE,SERIAL,FSTYPE,LABEL,MOUNTPOINTS || true
    echo "Virtio block-device serials:"
    for block in /sys/block/vd*; do
      [ -d "$block" ] || continue
      printf '%s serial=' "$block"
      cat "$block/serial" 2>/dev/null || echo "<unavailable>"
    done
    echo "Virtio by-id links:"
    for link in /dev/disk/by-id/virtio-*; do
      [ -e "$link" ] || continue
      printf '%s -> %s\n' "$link" "$(readlink "$link")"
    done
    echo "Recent kernel messages:"
    dmesg | tail -n 60 || true
  SCRIPT
end
