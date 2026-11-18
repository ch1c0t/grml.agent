BUILD_PROFILE_ROOT = "/mnt/shared/profiles"
BUILD_PROFILE_BUILDER_PACKAGES = "builder-packages.txt"
BUILD_PROFILE_BUILTIN_CLASSES = LiveBuildManifest::BUILTIN_CLASSES
BUILD_PROFILE_CONFIG_DIRECTORIES = %w(package_config debconf env files hooks scripts media-files media-scripts tools)

def validate_profile(profile_name : String, progress : Proc(String, Nil)? = nil) : LiveBuildManifest
  validate_build_profile_name(profile_name)
  profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
  manifest_path = "#{profile_directory}/grml-live/build.yml"

  verify_profile_tree(profile_directory)
  report_build_profile_progress(progress, "Reading grml-live build manifest for '#{profile_name}'")
  manifest = read_build_manifest(manifest_path)
  manifest.validate!

  report_build_profile_progress(progress, "Validating builder package list")
  packages = read_builder_packages(profile_directory)
  report_build_profile_progress(progress, "Builder packages: #{packages.size}")

  report_build_profile_progress(progress, "Checking custom grml-live classes")
  validate_profile_classes(profile_directory, manifest)
  report_build_profile_progress(progress, "Profile '#{profile_name}' is valid")
  manifest
end

private def validate_build_profile_name(profile_name : String) : Nil
  unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end
end

private def verify_profile_tree(profile_directory : String) : Nil
  command = <<-SHELL
    set -eu
    if [ ! -d '#{profile_directory}' ]; then
      echo "Profile directory not found: #{profile_directory}" >&2
      exit 2
    fi
    if [ ! -f '#{profile_directory}/grml-live/build.yml' ]; then
      echo "Missing grml-live build manifest: #{profile_directory}/grml-live/build.yml" >&2
      exit 2
    fi
    links=$(find '#{profile_directory}' -type l -print)
    if [ -n "$links" ]; then
      echo "Profile files must not be symbolic links:" >&2
      printf '%s\\n' "$links" >&2
      exit 3
    fi
    SHELL
  result = @interaction.execute(command)
  unless result.success?
    raise "Profile directory validation failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end

private def read_build_manifest(path : String) : LiveBuildManifest
  command = <<-SHELL
    set -eu
    manifest='#{path}'
    if [ ! -f "$manifest" ]; then
      echo "Missing grml-live build manifest: $manifest" >&2
      exit 2
    fi
    python3 - "$manifest" <<'PY'
    import datetime
    import json
    import sys
    import yaml

    allowed = {
        "suite", "classes", "hostname", "username", "distri_name",
        "distri_info", "grml_name", "release_name", "version",
        "boot_options", "secure_boot", "release", "bootstrap_mirror_url",
        "grml_live_ref", "iso_name", "date", "source_date_epoch",
    }

    def normalize(value):
        if isinstance(value, (datetime.date, datetime.datetime)):
            return value.isoformat()
        raise TypeError(f"Unsupported YAML value: {type(value).__name__}")

    try:
        with open(sys.argv[1], encoding="utf-8") as manifest_file:
            data = yaml.safe_load(manifest_file)
        if not isinstance(data, dict):
            raise ValueError("Manifest root must be a YAML mapping")
        unknown = sorted(set(data) - allowed)
        if unknown:
            raise ValueError("Unknown manifest key(s): " + ", ".join(unknown))
        print(json.dumps(data, default=normalize))
    except Exception as error:
        print(f"Invalid grml-live build manifest: {error}", file=sys.stderr)
        sys.exit(3)
    PY
    SHELL

  result = @interaction.execute(command, 30.seconds)
  unless result.success?
    raise "Could not read grml-live build manifest (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end

  LiveBuildManifest.from_json(result.stdout)
rescue ex : JSON::ParseException
  raise "Could not parse grml-live build manifest JSON: #{ex.message}"
end

private def read_builder_packages(profile_directory : String) : Array(String)
  packages_file = "#{profile_directory}/#{BUILD_PROFILE_BUILDER_PACKAGES}"
  command = <<-SHELL
    set -eu
    packages_file='#{packages_file}'
    [ -f "$packages_file" ] || exit 0
    awk '
      {
        sub(/#.*/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 == "") next
        if ($0 !~ /^[a-z0-9][a-z0-9+.-]*$/) {
          printf "Invalid Debian builder package name on line %d: %s\\\\n", NR, $0 > "/dev/stderr"
          exit 2
        }
        print
      }
    ' "$packages_file"
    SHELL
  result = @interaction.execute(command)
  unless result.success?
    raise "Could not read builder package list (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end

  result.stdout.lines.map(&.strip).reject(&.empty?).uniq
end

private def validate_profile_classes(profile_directory : String, manifest : LiveBuildManifest) : Nil
  custom_classes = manifest.classes.reject { |class_name| BUILD_PROFILE_BUILTIN_CLASSES.includes?(class_name) }
  return if custom_classes.empty?

  config_directory = "#{profile_directory}/grml-live/config"
  command = <<-SHELL
    set -eu
    config='#{config_directory}'
    for class_name in #{custom_classes.map { |name| shell_quote(name) }.join(" ")}; do
      found=0
      for category in #{BUILD_PROFILE_CONFIG_DIRECTORIES.join(" ")}; do
        if [ -e "$config/$category/$class_name" ]; then
          found=1
          break
        fi
      done
      if [ "$found" -ne 1 ]; then
        echo "Custom class '$class_name' has no definition under $config" >&2
        exit 4
      fi
    done
    SHELL

  result = @interaction.execute(command)
  unless result.success?
    raise "Profile class validation failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end

private def shell_quote(value : String) : String
  "'" + value.gsub("'", "'\\\\''") + "'"
end

private def report_build_profile_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call("#{message}\\n")
  else
    Log.info { message }
  end
end
