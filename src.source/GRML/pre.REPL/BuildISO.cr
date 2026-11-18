def build_iso(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  unless arguments.size == 1
    raise ArgumentError.new("Usage: build_iso PROFILE_NAME")
  end

  profile_name = arguments.first
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  agent.verify_shared_directory
  agent.build_iso(profile_name, progress)
end
