DEBIAN_PROFILE_DIRECTORY = "/mnt/shared/profiles"
DEBIAN_PROFILE_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

def apply_profile(
  profile_name : String,
  verify_cache : Bool = false,
  progress : Proc(String, Nil)? = nil
) : Nil
  unless profile_name.matches?(DEBIAN_PROFILE_NAME_PATTERN)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end

  packages_file = "#{DEBIAN_PROFILE_DIRECTORY}/#{profile_name}/packages.txt"
  report_profile_progress(progress, "Reading package list for profile '#{profile_name}'")

  command = <<-SHELL
    set -eu
    packages_file='#{packages_file}'
    if [ ! -f "$packages_file" ]; then
      echo "Package profile not found: $packages_file" >&2
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
    raise "Could not read package profile '#{profile_name}' (exit=#{profile_result.exit_code}, stderr=#{profile_result.stderr.inspect})"
  end

  packages = profile_result.stdout.lines.map(&.strip).reject(&.empty?).uniq
  if packages.empty? && !verify_cache
    report_profile_progress(progress, "Profile '#{profile_name}' contains no packages; skipping APT cache preparation")
    return
  end

  report_profile_progress(progress, "Preparing shared Debian package cache for profile '#{profile_name}'")
  prepare_deb_cache(progress)

  unless packages.empty?
    report_profile_progress(progress, "Installing #{packages.size} package(s) from profile '#{profile_name}'")
    install_command = <<-SHELL
      set -eu
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}
      SHELL

    result = @interaction.execute_streaming(install_command, 30.minutes) do |_stream, chunk|
      report_profile_output(progress, chunk)
    end
    unless result.success?
      raise "Could not install packages for profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
    end
    report_profile_progress(progress, "Profile '#{profile_name}' packages installed")
  end

  if verify_cache
    report_profile_progress(progress, "Verifying shared Debian package cache after applying profile '#{profile_name}'")
    verify_deb_cache("hello", progress)
  end
end

private def report_profile_output(progress : Proc(String, Nil)?, chunk : String) : Nil
  return if chunk.empty?

  if callback = progress
    callback.call(chunk)
  else
    Log.info { chunk }
  end
end

private def report_profile_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call("#{message}\n")
  else
    Log.info { message }
  end
end
