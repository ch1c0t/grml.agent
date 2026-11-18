private def validate_disk_format(format : String) : Nil
  unless DISK_FORMATS.includes?(format)
    raise ArgumentError.new("Unsupported disk format #{format.inspect}; choose qcow2 or raw")
  end
end
