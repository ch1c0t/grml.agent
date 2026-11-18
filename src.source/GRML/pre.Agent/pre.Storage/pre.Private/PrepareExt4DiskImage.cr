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
  report_storage_progress(progress, "Verifying disk image size and format")
  verify_disk_image_size(path, format, size)
  path
end
