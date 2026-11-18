private def run_build_environment_command(command, timeout, progress, label = "command") : Nil
  stdout, stderr = IO::Memory.new, IO::Memory.new
  wrapped = build_environment_diagnostic_command(command, label)
  result = @interaction.execute_streaming(wrapped, timeout) do |stream, chunk|
    (stream == :stderr ? stderr : stdout).write(chunk.to_slice)
    report_build_environment_output(progress, chunk)
  end
  return if result.success?
  stdout_text = stdout.to_s.empty? ? result.stdout : stdout.to_s
  stderr_text = stderr.to_s.empty? ? result.stderr : stderr.to_s
  raise build_environment_command_error(label, result.exit_code, stdout_text, stderr_text)
end
