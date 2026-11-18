private def verify_disk_image_size(path : String, format : String, requested_size : String) : Nil
  match = /\A([1-9][0-9]*)([KMGTP])?\z/i.match(requested_size)
  raise ArgumentError.new("Invalid disk size: #{requested_size.inspect}") unless match

  multiplier = case match[2]?.try(&.upcase)
               when "K" then 1024_i64
               when "M" then 1024_i64 ** 2
               when "G" then 1024_i64 ** 3
               when "T" then 1024_i64 ** 4
               when "P" then 1024_i64 ** 5
               else        1_i64
               end
  expected_bytes = match[1].to_i64 * multiplier

  output = IO::Memory.new
  error = IO::Memory.new
  result = Process.run("qemu-img", ["info", "--output=json", "-f", format, path], output: output, error: error)
  unless result.success?
    raise "qemu-img could not inspect #{path} (#{result.exit_code}): #{error.to_s.strip}"
  end

  actual_bytes = JSON.parse(output.to_s).as_h["virtual-size"].as_i
  if actual_bytes < expected_bytes
    raise "Disk image #{path} is too small: #{actual_bytes} bytes, #{expected_bytes} required"
  end
end
