private def profile_dependencies(profile_name : String) : Array(String)
  path = File.join(@vm.shared_path, "profiles", profile_name, "profiles.txt")
  return [] of String unless File.file?(path)

  dependencies = [] of String
  File.each_line(path) do |line|
    name = line.sub(/#.*/, "").strip
    next if name.empty?
    unless name.matches?(DEBIAN_PROFILE_NAME_PATTERN)
      raise ArgumentError.new("Invalid profile dependency in #{path}: #{line.inspect}")
    end
    raise ArgumentError.new("Duplicate profile dependency '#{name}' in #{path}") if dependencies.includes?(name)
    dependencies << name
  end
  dependencies
end
