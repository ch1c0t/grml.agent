private def validate_disk_name(name : String) : Nil
  unless name.matches?(DISK_NAME_PATTERN)
    raise ArgumentError.new("Invalid disk name: #{name.inspect}")
  end
end
