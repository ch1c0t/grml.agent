def copy_executable(agent : T, arguments : Array(String)) : String forall T
  unless arguments.size == 2
    raise ArgumentError.new("Usage: copy_executable <host_path> <guest_path>")
  end
  source = arguments[0]
  destination = arguments[1]
  agent.copy_executable_to_guest(source, destination)
  "Copied executable #{source} to guest at #{destination} (mode 0755)."
end
