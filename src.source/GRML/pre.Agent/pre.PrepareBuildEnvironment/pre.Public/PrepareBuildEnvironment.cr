def prepare_build_environment(profile_name : String, progress : Proc(String, Nil)? = nil) : Nil
  validate_build_profile_name(profile_name)
  profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"

  report_build_profile_progress(progress, "Preparing grml-live build environment for '#{profile_name}'")
  verify_profile_tree(profile_directory)
  packages = read_builder_packages(profile_directory)
  manifest = validate_profile(profile_name, progress)
  all_packages = (GRML_LIVE_BUILDER_PACKAGES + packages).uniq

  report_build_profile_progress(progress, "Preparing shared Debian package cache")
  prepare_deb_cache(progress)

  report_build_environment_stage(1, "Installing grml-live build dependencies", progress) do
    command = "set -eu; apt-get update; " +
      "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{all_packages.join(" ")}"
    run_build_environment_command(command, 45.minutes, progress)
  end

  report_build_environment_stage(2, "Creating the unprivileged build account and subordinate ID mappings", progress) do
    command = <<-SHELL
      set -eu
      if ! id '#{GRML_LIVE_BUILDER}' >/dev/null 2>&1; then
        useradd --create-home --user-group --shell /bin/bash '#{GRML_LIVE_BUILDER}'
      fi

      python3 - <<'PY'
      from pathlib import Path

      username = "#{GRML_LIVE_BUILDER}"
      count = 65536

      def ensure_range(filename):
          path = Path(filename)
          path.touch(exist_ok=True)
          entries = []
          for raw_line in path.read_text(encoding="utf-8").splitlines():
              fields = raw_line.split(":")
              if len(fields) != 3:
                  continue
              try:
                  start, size = int(fields[1]), int(fields[2])
              except ValueError:
                  continue
              entries.append((fields[0], start, size))

          if any(name == username and size >= count for name, start, size in entries):
              return

          start = 100000
          while True:
              overlapping = [
                  (other_start, other_start + other_size)
                  for name, other_start, other_size in entries
                  if start < other_start + other_size and start + count > other_start
              ]
              if not overlapping:
                  break
              start = max(end for _, end in overlapping)

          with path.open("a", encoding="utf-8") as stream:
              stream.write(f"{username}:{start}:{count}\\n")

      ensure_range("/etc/subuid")
      ensure_range("/etc/subgid")
      PY

      runuser -u '#{GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
      SHELL
    run_build_environment_command(command, 60.seconds, progress)
  end

  report_build_environment_stage(3, "Provisioning persistent ext4 build workspace", progress) do
    ensure_build_workspace(progress)
  end

  report_build_environment_stage(4, "Checking out grml-live source", progress) do
    checkout_grml_live(manifest.grml_live_ref, progress)
    nil
  end

  report_build_profile_progress(progress, "grml-live build environment is ready")
end
