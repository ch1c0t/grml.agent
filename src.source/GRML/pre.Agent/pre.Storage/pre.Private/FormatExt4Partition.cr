private def format_ext4_partition : String
  <<-SCRIPT
    filesystem=$(blkid -p -o value -s TYPE "$partition" 2>/dev/null || true)
    if [ -z "$filesystem" ]; then
      echo "Formatting new partition as ext4 (mkfs.ext4)"
      mkfs.ext4 -F "$partition"
    elif [ "$filesystem" != ext4 ]; then
      echo "Existing partition has filesystem '$filesystem'; refusing to format it" >&2
      exit 1
    else
      echo "Reusing existing ext4 filesystem"
    fi
  SCRIPT
end
