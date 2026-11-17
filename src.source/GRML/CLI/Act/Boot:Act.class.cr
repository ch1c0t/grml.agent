def validate_arguments
  args = @arguments.dup
  until args.empty?
    argument = args.shift
    case argument
    when "--iso"
      if args.empty? || @boot_iso_path
        usage_error
      end
      @boot_iso_path = args.shift
    when "--verify-deb-cache"
      if @boot_verify_deb_cache
        usage_error
      end
      @boot_verify_deb_cache = true
    else
      if argument.starts_with?("-") || @boot_profile
        usage_error
      end
      unless argument.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
        usage_error
      end
      @boot_profile = argument
    end
  end

  usage_error if @boot_verify_deb_cache && !@boot_profile
end

private def usage_error : NoReturn
  STDERR.puts "Usage: grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]"
  exit 1
end

protected def perform(agent : GRML::Agent) : Nil
  Log.info { "GRML agent is running. Starting REPL." }
  GRML::REPL.run(agent)
end
