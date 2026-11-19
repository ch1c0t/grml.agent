private def checkout_grml_live_ref(ref : String, progress : Proc(String, Nil)?) : String
  unless ref.matches?(/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/) && !ref.split('/').includes?("..")
    raise ArgumentError.new("Invalid grml-live git ref: #{ref.inspect}")
  end
  result = @interaction.execute_streaming(checkout_grml_live_command(ref), 10.minutes) do |_stream, chunk|
    report_build_environment_output(progress, chunk)
  end
  unless result.success?
    raise "Could not check out grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
end
