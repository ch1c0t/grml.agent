def apply_profile(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  unless arguments.size == 1
    raise ArgumentError.new("Usage: apply_profile PROFILE_NAME")
  end

  profile_name = arguments.first
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  agent.apply_profile(profile_name, false, progress)
  "Applied package profile '#{profile_name}'. Package installation is additive; other packages are not removed."
end
