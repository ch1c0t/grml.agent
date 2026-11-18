private def prepare_ext4_disk_image(name, size, format, progress) : String
  validate_disk_name(name)
  raise ArgumentError.new("Invalid disk size: #{size.inspect}") unless size.matches?(DISK_SIZE_PATTERN)
  validate_disk_format(format)
  path = File.join(File.expand_path("./disks"), "#{name}.#{format}")
  if File.exists?(path)
    raise "Disk image path is not a regular file: #{path}" unless File.file?(path)
    report_storage_progress(progress, "Reusing host disk image: #{path}")
  else
    report_storage_progress(progress, "Creating sparse #{size} disk image: #{path}")
    path = create_disk_image(name, size, format)
  end
  suffix = name == "grml-live-build" ? "live_build" : name.gsub(/[^A-Za-z0-9_-]/, "_")
  attached = find_named_block_node("grml_disk_#{suffix}")
  if attached
    report_storage_progress(progress, "Verifying attached image metadata through QMP")
    verify_attached_disk_image(attached, path, format, size)
  else
    report_storage_progress(progress, "Verifying detached disk image size and format")
    verify_disk_image_size(path, format, size)
  end
  path
end
