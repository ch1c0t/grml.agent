private def download_profile_executable(name : String, url : String) : String
  path = File.join(Dir.tempdir, "grml-agent-#{name}-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
  result = Process.run(["curl", "--fail", "--location", "--show-error", "--output", path, url],
    output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  unless result.success? && File.file?(path) && File.size(path) > 0
    raise "curl failed to download '#{name}' (exit=#{result.exit_code})"
  end
  path
rescue error
  File.delete(path) if File.exists?(path)
  raise "Could not download host executable '#{name}' from #{url}: #{error.message}"
end
