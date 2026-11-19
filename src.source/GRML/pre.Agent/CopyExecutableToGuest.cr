def copy_executable_to_guest(source : String, destination : String) : Nil
  source_path = File.expand_path(source)
  raise "Host executable does not exist: #{source_path}" unless File.file?(source_path)
  unless destination.starts_with?("/") && destination != "/" && !destination.ends_with?("/")
    raise ArgumentError.new("Guest destination must be an absolute file path: #{destination.inspect}")
  end
  verify_shared_directory
  staged_path = nil.as(String?)
  begin
    staged_name = ".grml-agent-upload-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}"
    staged_path = File.join(@vm.shared_path, staged_name)
    File.copy(source_path, staged_path)
    guest_path = File.join("/mnt/shared", staged_name)
    command = "install -D -m 0755 -- #{shell_quote(guest_path)} #{shell_quote(destination)}"
    result = @interaction.execute(command, 5.minutes)
    unless result.success?
      raise "Guest executable installation failed (exit=#{result.exit_code}): #{result.stderr}"
    end
  ensure
    if path = staged_path
      File.delete(path) if File.exists?(path)
    end
  end
end
