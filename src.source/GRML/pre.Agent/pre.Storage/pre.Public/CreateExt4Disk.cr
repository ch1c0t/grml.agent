def create_ext4_disk(
  name : String,
  size : String,
  mountpoint : String? = nil,
  format : String = "qcow2"
) : String
  validate_disk_name(name)
  validate_disk_format(format)
  guest_mountpoint = validate_guest_mountpoint(mountpoint || "/mnt/#{name}")

  path = create_disk_image(name, size, format)

  attached = begin
    attach_disk_with_serial(path, format)
  rescue ex
    File.delete(path) if File.exists?(path)
    raise ex
  end

  begin
    result = @interaction.execute(
      ext4_provisioning_command(attached[:serial], guest_mountpoint),
      2.minutes
    )

    unless result.success?
      details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
      message = "Guest provisioning command exited with status #{result.exit_code}"
      message += ":\n#{details}" unless details.empty?
      raise message
    end
  rescue ex
    raise "Disk image #{path} remains attached as #{attached[:device_id]}, but guest partitioning, ext4 formatting, or mounting failed: #{ex.message}"
  end

  "#{path} (ext4 mounted at #{guest_mountpoint})"
end
