private def mount_ext4_partition : String
  <<-SCRIPT
    echo "Mounting ext4 workspace at $mountpoint"
    mkdir -p "$mountpoint"
    mount -t ext4 "$partition" "$mountpoint"
    echo "Verifying mounted filesystem"
    findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
    printf 'Mounted %s on %s as ext4\\n' "$partition" "$mountpoint"
  SCRIPT
end
