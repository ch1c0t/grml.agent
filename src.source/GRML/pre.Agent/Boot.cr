def boot(profile_name : String? = nil, verify_cache : Bool = false) : Nil
  if verify_cache && profile_name.nil?
    raise ArgumentError.new("--verify-deb-cache requires a boot profile")
  end

  navigate_boot_menu
  wait_for_shell
  verify_guest_agent
  configure_console
  verify_shared_directory

  Log.info { "GRML shared directory is operational" }
  install_profile_packages(profile_name, verify_cache) if profile_name
end

private def install_profile_packages(profile_name : String, verify_cache : Bool) : Nil
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  packages_file = "/mnt/shared/profiles/#{profile_name}/packages.txt"
  Log.info { "Reading package list for boot profile '#{profile_name}'" }
  command = <<-SHELL
    set -eu
    packages_file='#{packages_file}'
    if [ ! -f "$packages_file" ]; then
      echo "Boot profile package list not found: $packages_file" >&2
      exit 2
    fi

    awk '
      {
        sub(/#.*/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 == "") next
        if ($0 !~ /^[a-z0-9][a-z0-9+.-]*$/) {
          printf "Invalid Debian package name on line %d: %s\\n", NR, $0 > "/dev/stderr"
          exit 2
        }
        print
      }
    ' "$packages_file"
    SHELL

  profile_result = @interaction.execute(command)
  unless profile_result.success?
    raise "Could not read boot profile '#{profile_name}' packages (exit=#{profile_result.exit_code}, stderr=#{profile_result.stderr.inspect})"
  end

  packages = profile_result.stdout.lines.map(&.strip).reject(&.empty?)
  if packages.empty? && !verify_cache
    Log.info { "Boot profile '#{profile_name}' contains no packages; skipping APT cache preparation" }
    return
  end

  progress = ->(message : String) do
    STDOUT.print(message)
    STDOUT.flush
  end

  Log.info { "Preparing shared Debian package cache for boot profile '#{profile_name}'" }
  prepare_deb_cache(progress)

  unless packages.empty?
    Log.info { "Installing #{packages.size} package(s) from boot profile '#{profile_name}'" }
    install_command = <<-SHELL
      set -eu
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}
      SHELL

    result = @interaction.execute_streaming(install_command, 30.minutes) do |_stream, chunk|
      STDOUT.print(chunk)
      STDOUT.flush
    end
    unless result.success?
      raise "Could not install packages for boot profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
    end
    Log.info { "Boot profile '#{profile_name}' packages installed" }
  end

  if verify_cache
    Log.info { "Verifying shared Debian package cache after installing boot profile '#{profile_name}'" }
    verify_deb_cache("hello", progress)
  end
end

private def navigate_boot_menu : Nil
  Log.info { "Waiting for GRML boot prompt" }
  @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  Log.info { "Sending Return to GRML boot prompt" }
  @vm.send_key("ret")

  Log.info { "Waiting for GRML key prompt" }
  @interaction.wait_for_text("Press a key", region: :bottom_tenth)
  Log.info { "Sending Return to GRML key prompt" }
  @vm.send_key("ret")
end

private def wait_for_shell : Nil
  Log.info { "Waiting for GRML shell prompt" }
  @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
end

private def verify_guest_agent : Nil
  Log.info { "GRML command line ready; checking QEMU Guest Agent" }
  result = @interaction.execute("printf 'qemu-guest-agent-ok\\n'")
  unless result.success? && result.stdout.strip == "qemu-guest-agent-ok"
    raise "QEMU Guest Agent test failed (exit=#{result.exit_code}, stdout=#{result.stdout.inspect}, stderr=#{result.stderr.inspect})"
  end
  Log.info { "QEMU Guest Agent is operational" }
end

private def configure_console : Nil
  Log.info { "Setting GRML console font size to 12x24" }
  result = @interaction.execute("sed -i 's|^FONTSIZE=.*|FONTSIZE=\\\"12x24\\\"|' /etc/default/console-setup && grep -Fqx 'FONTSIZE=\\\"12x24\\\"' /etc/default/console-setup && setupcon")
  unless result.success?
    raise "Could not configure GRML console font size (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  Log.info { "GRML console font size set to 12x24" }
end
