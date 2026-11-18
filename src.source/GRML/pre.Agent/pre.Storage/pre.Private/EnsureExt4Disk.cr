private def ensure_ext4_disk(
  name : String, size : String, mountpoint : String,
  format : String = "qcow2", progress : Proc(String, Nil)? = nil
) : String
  guest_mountpoint = validate_guest_mountpoint(mountpoint)
  path = prepare_ext4_disk_image(name, size, format, progress)
  ensure_ext4_disk_attachment(path, name, format, progress)
  provision_ext4_disk(name, guest_mountpoint, path, progress)
  "#{path} (ext4 mounted at #{guest_mountpoint})"
end
