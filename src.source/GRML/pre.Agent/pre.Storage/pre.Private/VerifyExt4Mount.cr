private def verify_ext4_mount : String
  <<-SCRIPT
    if mountpoint -q "$mountpoint"; then
      mounted_source=$(findmnt -n -o SOURCE --target "$mountpoint")
      mounted_type=$(findmnt -n -o FSTYPE --target "$mountpoint")
      if [ "$mounted_type" != ext4 ] || [ "$(readlink -f "$mounted_source")" != "$(readlink -f "$partition")" ]; then
        echo "Build workspace is mounted from another filesystem" >&2
        exit 1
      fi
      echo "Existing ext4 build workspace is already mounted at $mountpoint"
      exit 0
    fi
  SCRIPT
end
