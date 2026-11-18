private def expected_disk_image_size(requested_size : String) : Int64
  match = /\A([1-9][0-9]*)([KMGTP])?\z/i.match(requested_size)
  raise ArgumentError.new("Invalid disk size: #{requested_size.inspect}") unless match
  match[1].to_i64 * disk_size_multiplier(match[2]?.try(&.upcase))
end
