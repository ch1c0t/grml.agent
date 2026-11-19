def prepare_build_environment(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  unless arguments.size == 1
    raise ArgumentError.new("Usage: prepare_build_environment PROFILE_NAME")
  end

  profile_name = arguments.first
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  agent.verify_shared_directory
  agent.prepare_build_environment(profile_name, progress)
  "Prepared grml-live build environment for '#{profile_name}'."
end
