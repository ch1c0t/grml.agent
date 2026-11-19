private def profile_host_executables(profile_name : String) : Array(Tuple(String, String))
  path = File.join(@vm.shared_path, "profiles", profile_name, "host-executables.txt")
  return [] of Tuple(String, String) unless File.file?(path)

  entries = [] of Tuple(String, String)
  File.each_line(path) do |line|
    fields = line.sub(/#.*/, "").strip.split
    next if fields.empty?
    unless fields.size == 2 && fields[0].matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._+-]*\z/) &&
           fields[1].matches?(/\Ahttps:\/\/[^\s]+\z/)
      raise ArgumentError.new("Invalid host-executable entry in #{path}: #{line.inspect}")
    end
    raise ArgumentError.new("Duplicate host executable: #{fields[0]}") if entries.any? { |entry| entry[0] == fields[0] }
    entries << {fields[0], fields[1]}
  end
  entries
end
