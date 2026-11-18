private def ensure_grml_live_checkout_for_build(ref : String, progress : Proc(String, Nil)?) : String
  command = <<-SHELL
    set -eu
    if [ ! -x '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live' ]; then
      echo "grml-live is not installed; run prepare_build_environment PROFILE_NAME first" >&2
      exit 10
    fi
    git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' fetch --force --depth=1 origin '#{ref}'
    git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' checkout --force --detach FETCH_HEAD
    git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' clean -fdx
    git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' rev-parse HEAD
    SHELL

  result = @interaction.execute_streaming(command, 10.minutes) do |_stream, chunk|
    report_build_environment_output(progress, chunk)
  end
  unless result.success?
    raise "Could not select grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
end
