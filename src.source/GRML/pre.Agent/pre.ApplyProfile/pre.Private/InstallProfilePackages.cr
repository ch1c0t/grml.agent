private def install_profile_packages(profile_name : String, packages : Array(String),
                                      progress : Proc(String, Nil)?) : Nil
  report_profile_progress(progress, "Preparing shared Debian package cache for profile '#{profile_name}'")
  prepare_deb_cache(progress)
  report_profile_progress(progress, "Installing #{packages.size} package(s) from profile '#{profile_name}'")
  command = "set -eu; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}"
  result = @interaction.execute_streaming(command, 30.minutes) do |_stream, chunk|
    report_profile_output(progress, chunk)
  end
  unless result.success?
    raise "Could not install packages for profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  report_profile_progress(progress, "Profile '#{profile_name}' packages installed")
end
