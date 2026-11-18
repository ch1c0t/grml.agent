private def validate_guest_mountpoint(path : String) : String
  unless path.starts_with?("/") && path != "/" && !path.split("/").any? { |part| part == "." || part == ".." }
    raise ArgumentError.new("Mount point must be an absolute guest path without '.' or '..' components: #{path.inspect}")
  end
  path
end
