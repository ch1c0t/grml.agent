private def read_profile_packages(profile_name : String, progress : Proc(String, Nil)?) : Array(String)
  path = "#{DEBIAN_PROFILE_DIRECTORY}/#{profile_name}/packages.txt"
  report_profile_progress(progress, "Reading package list for profile '#{profile_name}'")
  command = <<-SHELL
    set -eu
    packages_file='#{path}'
    if [ ! -f "$packages_file" ]; then
      echo "Package profile not found: $packages_file" >&2
      exit 2
    fi
    awk '
      { sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 == "") next
        if ($0 !~ /^[a-z0-9][a-z0-9+.-]*$/) {
          printf "Invalid Debian package name on line %d: %s\\n", NR, $0 > "/dev/stderr"
          exit 2
        }
        print
      }
    ' "$packages_file"
    SHELL
  result = @interaction.execute(command)
  unless result.success?
    raise "Could not read package profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  result.stdout.lines.map(&.strip).reject(&.empty?).uniq
end
