private def ensure_ext4_disk(
  name : String,
  size : String,
  mountpoint : String,
  format : String = "qcow2"
) : String
  validate_disk_name(name)
  unless size.matches?(DISK_SIZE_PATTERN)
    raise ArgumentError.new("Invalid disk size: #{size.inspect}; use e.g. 10G")
  end
  validate_disk_format(format)
  guest_mountpoint = validate_guest_mountpoint(mountpoint)

  directory = File.expand_path("./disks")
  path = File.join(directory, "#{name}.#{format}")
  if File.exists?(path)
    raise "Build disk path exists but is not a regular file: #{path}" unless File.file?(path)
  else
    path = create_disk_image(name, size, format)
  end

  verify_disk_image_size(path, format, size)

  suffix = "live_build"
  device_id = "grml_virtio_disk_#{suffix}"
  serial = "grml-live-build"
  attached_path = find_attached_disk_path(device_id)

  if attached_path
    unless File.expand_path(attached_path) == path
      raise "QEMU device #{device_id} is already attached to a different disk image: #{attached_path}"
    end
  else
    attach_disk_with_serial(path, format, suffix, serial)
  end

  result = @interaction.execute(
    ensure_ext4_provisioning_command(serial, guest_mountpoint),
    2.minutes
  )
  unless result.success?
    details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
    message = "Could not ensure the persistent ext4 build workspace (exit=#{result.exit_code})"
    message += ":\n#{details}" unless details.empty?
    raise "#{message}. Disk image is retained at #{path} for recovery."
  end

  "#{path} (ext4 mounted at #{guest_mountpoint})"
end
