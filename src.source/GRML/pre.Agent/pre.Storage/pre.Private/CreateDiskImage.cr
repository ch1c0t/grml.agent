private def create_disk_image(name : String, size : String, format : String) : String
  validate_disk_name(name)

  unless size.matches?(DISK_SIZE_PATTERN)
    raise ArgumentError.new("Invalid disk size: #{size.inspect}; use e.g. 10G")
  end
  validate_disk_format(format)

  directory = File.expand_path("./disks")
  Dir.mkdir_p(directory)
  path = File.join(directory, "#{name}.#{format}")
  raise "Disk already exists: #{path}" if File.exists?(path)

  output = IO::Memory.new
  error = IO::Memory.new
  result = Process.run("qemu-img", ["create", "-f", format, path, size], output: output, error: error)
  unless result.success?
    raise "qemu-img failed (#{result.exit_code}): #{error.to_s.strip}"
  end

  path
end
