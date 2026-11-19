private def ensure_ext4_disk_attachment(path, name, format, progress) : Nil
  suffix = name == "grml-live-build" ? "live_build" : name.gsub(/[^A-Za-z0-9_-]/, "_")
  device_id = "grml_virtio_disk_#{suffix}"
  if find_attached_disk_info_by_path(path)
    report_storage_progress(progress, "Reusing QEMU disk attachment for image: #{path}")
  else
    report_storage_progress(progress, "Attaching disk to QEMU: #{device_id}")
    attach_disk_with_serial(path, format, suffix, name)
  end
end
