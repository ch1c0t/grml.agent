private def write_storage_diagnostics(path : String, node_name : String) : String
  state = ENV["XDG_STATE_HOME"]? || File.join(ENV["HOME"]? || "/tmp", ".local", "state")
  directory = File.join(state, "grml-agent", "storage")
  Dir.mkdir_p(directory)
  name = "build-workspace-#{Time.utc.to_s("%Y%m%dT%H%M%S")}-#{Process.pid}.json"
  report = File.join(directory, name)
  File.write(report, storage_diagnostics_payload(path, node_name))
  report
end
