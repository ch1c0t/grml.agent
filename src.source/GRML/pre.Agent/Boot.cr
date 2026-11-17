def boot(profile_name : String? = nil) : Nil
  navigate_boot_menu
  wait_for_shell
  verify_guest_agent
  configure_console
  verify_shared_directory

  Log.info { "GRML shared directory is operational" }
  install_profile_packages(profile_name) if profile_name
end

private def install_profile_packages(profile_name : String) : Nil
  unless profile_name.matches?(/\\A[a-zA-Z0-9][a-zA-Z0-9._-]*\\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  packages_file = "/mnt/shared/profiles/#{profile_name}/packages.txt"
  Log.info { "Installing packages from boot profile '#{profile_name}'" }
  command = <<-SHELL
    set -eu
    packages_file='#{packages_file}'
    if [ ! -f "$packages_file" ]; then
      echo "Boot profile package list not found: $packages_file" >&2
      exit 2
    fi
    packages=$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$packages_file" | sed '/^$/d')
    if [ -z "$packages" ]; then
      echo "Boot profile '#{profile_name}' contains no packages"
      exit 0
    fi
    if ! printf '%s\\n' "$packages" | awk 'BEGIN { ok = 1 } !/^[a-z0-9][a-z0-9+.-]*$/ { ok = 0 } END { exit !ok }'; then
      echo "Invalid Debian package name in $packages_file" >&2
      exit 2
    fi
    apt-get update
    printf '%s\\n' "$packages" | xargs -r apt-get install -y --no-install-recommends
    SHELL

  result = @interaction.execute_streaming(command, 30.minutes) do |_stream, chunk|
    STDOUT.print(chunk)
  end
  unless result.success?
    raise "Could not install packages for boot profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  Log.info { "Boot profile '#{profile_name}' packages installed" }
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
  result = @interaction.execute("sed -i 's|^FONTSIZE=.*|FONTSIZE=\"12x24\"|' /etc/default/console-setup && grep -Fqx 'FONTSIZE=\"12x24\"' /etc/default/console-setup && setupcon")
  unless result.success?
    raise "Could not configure GRML console font size (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  Log.info { "GRML console font size set to 12x24" }
end
