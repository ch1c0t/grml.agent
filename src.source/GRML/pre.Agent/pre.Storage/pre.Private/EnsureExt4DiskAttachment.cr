private def ensure_ext4_disk_attachment(path, name, format, progress) : Nil
  suffix = name == "grml-live-build" ? "live_build" : name.gsub(/[^A-Za-z0-9_-]/, "_")
  device_id = "grml_virtio_disk_#{suffix}"
  attached_path = find_attached_disk_path(device_id)
  if attached_path
    unless File.expand_path(attached_path) == path
      raise "QEMU device #{device_id} is attached to another image: #{attached_path}"
    end
    report_storage_progress(progress, "Reusing QEMU disk attachment: #{device_id}")
  else
    report_storage_progress(progress, "Attaching disk to QEMU: #{device_id}")
    attach_disk_with_serial(path, format, suffix, name)
  end
end
