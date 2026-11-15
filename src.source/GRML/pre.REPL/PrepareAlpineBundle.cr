DEFAULT_ALPINE_BRANCH = "latest-stable"

def alpine_branch(arguments : Array(String)) : String
  raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]") if arguments.size > 1
  branch = arguments.first? || DEFAULT_ALPINE_BRANCH
  raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}") unless branch =~ /\A[a-zA-Z0-9._-]+\z/
  branch
end

def prepare_alpine_bundle(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  branch = alpine_branch(arguments)
  agent.prepare_alpine_bundle(branch, progress)
  "Prepared Alpine offline bundle (branch: #{branch})."
end
