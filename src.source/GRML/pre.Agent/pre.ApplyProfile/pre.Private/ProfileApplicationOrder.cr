private def profile_application_order(profile_name : String) : Array(String)
  ordered = [] of String
  visit_profile(profile_name, [] of String, [] of String, ordered)
  ordered
end

private def visit_profile(name : String, visiting : Array(String),
                          visited : Array(String), ordered : Array(String)) : Nil
  unless name.matches?(DEBIAN_PROFILE_NAME_PATTERN)
    raise ArgumentError.new("Invalid profile name: #{name.inspect}")
  end
  if index = visiting.index(name)
    cycle = visiting[index..(visiting.size - 1)] + [name]
    raise ArgumentError.new("Profile dependency cycle: #{cycle.join(" -> ")}")
  end
  return if visited.includes?(name)
  visiting << name
  profile_dependencies(name).each { |dependency| visit_profile(dependency, visiting, visited, ordered) }
  visiting.pop
  visited << name
  ordered << name
end
