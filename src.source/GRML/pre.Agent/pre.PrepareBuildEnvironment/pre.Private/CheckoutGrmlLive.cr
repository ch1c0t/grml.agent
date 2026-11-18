private def checkout_grml_live(ref : String, progress : Proc(String, Nil)? = nil) : String
  unless ref.matches?(/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/) && !ref.split('/').includes?("..")
    raise ArgumentError.new("Invalid grml-live git ref: #{ref.inspect}")
  end

  command = <<-SHELL
    set -eu
    if [ ! -d '#{GRML_LIVE_CHECKOUT}/.git' ]; then
      rm -rf '#{GRML_LIVE_CHECKOUT}'
      git clone --filter=blob:none --no-checkout https://github.com/grml/grml-live.git '#{GRML_LIVE_CHECKOUT}'
    fi
    git -C '#{GRML_LIVE_CHECKOUT}' fetch --force --depth=1 origin '#{ref}'
    git -C '#{GRML_LIVE_CHECKOUT}' checkout --force --detach FETCH_HEAD
    git -C '#{GRML_LIVE_CHECKOUT}' clean -fdx
    git -C '#{GRML_LIVE_CHECKOUT}' rev-parse HEAD
    SHELL

  result = @interaction.execute_streaming(command, 10.minutes) do |_stream, chunk|
    report_build_environment_output(progress, chunk)
  end
  unless result.success?
    raise "Could not check out grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end

  result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
end
