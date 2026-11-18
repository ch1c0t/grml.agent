def validate_profile(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  unless arguments.size == 1
    raise ArgumentError.new("Usage: validate_profile PROFILE_NAME")
  end

  profile_name = arguments.first
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  agent.verify_shared_directory
  manifest = agent.validate_profile(profile_name, progress)
  "Validated '#{profile_name}': suite=#{manifest.suite}, classes=#{manifest.classes_argument}."
end
