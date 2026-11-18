private def run_build_environment_command(
  command : String,
  timeout : Time::Span,
  progress : Proc(String, Nil)?
) : Nil
  result = @interaction.execute_streaming(command, timeout) do |_stream, chunk|
    report_build_environment_output(progress, chunk)
  end
  unless result.success?
    raise "Build environment command failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end
end
