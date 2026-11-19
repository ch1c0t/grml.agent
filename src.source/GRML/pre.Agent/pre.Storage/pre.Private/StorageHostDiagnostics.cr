private def storage_host_diagnostics(path : String) : JSON::Any
  owners = capture_storage_command("fuser", [path])
  pids = owners.as_h["stdout"]?.try(&.as_s).to_s.split.compact_map(&.to_i?).uniq
  processes = pids.map { |pid| capture_storage_command("ps", ["-ww", "-p", pid.to_s, "-o", "pid=,ppid=,user=,args="]) }
  JSON.parse({
    "fuser_verbose" => capture_storage_command("fuser", ["-v", path]),
    "fuser_pids" => owners, "owner_processes" => processes,
    "lslocks" => capture_storage_command("lslocks", ["--notruncate", "--output", "PID,COMMAND,TYPE,MODE,PATH"]),
    "qemu_processes" => capture_storage_command("pgrep", ["-af", "qemu-system-x86_64"])
  }.to_json)
end
