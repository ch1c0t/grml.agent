private def verify_build_environment(manifest : LiveBuildManifest) : Nil
  workspace = ::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_WORKSPACE
  minimum_bytes = manifest.classes.includes?("GRML_FULL") ? 4_i64 * 1024 * 1024 * 1024 : 2_i64 * 1024 * 1024 * 1024
  command = <<-SHELL
    set -eu
    test -x '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live'
    id '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' >/dev/null
    grep -q '^#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:' /etc/subuid
    grep -q '^#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:' /etc/subgid
    for program in dpkg mksquashfs mmdebstrap xorriso runuser unshare newuidmap newgidmap findmnt mountpoint blkid; do
      command -v "$program" >/dev/null || {
        echo "Required build program is missing: $program" >&2
        exit 11
      }
    done

    mountpoint -q '#{workspace}' || {
      echo "Build workspace is not mounted: #{workspace}" >&2
      exit 12
    }

    filesystem=$(findmnt -n -o FSTYPE --target '#{workspace}')
    if [ "$filesystem" != ext4 ]; then
      echo "Build workspace must be ext4, found: $filesystem" >&2
      exit 13
    fi

    mount_target=$(findmnt -n -o TARGET --target '#{workspace}')
    if [ "$mount_target" != '#{workspace}' ]; then
      echo "Build workspace is not a dedicated mount point: $mount_target" >&2
      exit 14
    fi

    mount_options=$(findmnt -n -o OPTIONS --target '#{workspace}')
    for option in nodev noexec nosuid; do
      case ",$mount_options," in
        *",$option,"*)
          echo "Build workspace is mounted with $option; grml-live requires an executable, device-capable filesystem" >&2
          exit 15
          ;;
      esac
    done

    free_bytes=$(df -PB1 '#{workspace}' | awk 'NR == 2 {print $4}')
    if [ "$free_bytes" -lt #{minimum_bytes} ]; then
      echo "Insufficient free space in #{workspace}: $free_bytes bytes available, #{minimum_bytes} required" >&2
      exit 16
    fi

    runuser -u '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
    SHELL
  result = @interaction.execute(command, 60.seconds)
  unless result.success?
    raise "grml-live build environment is not ready; run prepare_build_environment PROFILE_NAME (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end
