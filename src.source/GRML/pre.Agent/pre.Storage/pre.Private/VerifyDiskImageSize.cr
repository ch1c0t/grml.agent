private def verify_disk_image_size(path : String, format : String, requested_size : String) : Nil
  match = /\A([1-9][0-9]*)([KMGTP])?\z/i.match(requested_size)
  raise ArgumentError.new("Invalid disk size: #{requested_size.inspect}") unless match
  multiplier = disk_size_multiplier(match[2]?.try(&.upcase))
  expected_bytes = match[1].to_i64 * multiplier
  output, error = IO::Memory.new, IO::Memory.new
  result = Process.run("qemu-img", ["info", "--output=json", "-f", format, path], output: output, error: error)
  unless result.success?
    raise "qemu-img could not inspect #{path} (#{result.exit_code}): #{error}"
  end
  actual_bytes = disk_image_virtual_size(output.to_s)
  if actual_bytes < expected_bytes
    raise "Disk image #{path} is too small: #{actual_bytes} bytes, #{expected_bytes} required"
  end
end
