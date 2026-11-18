GRML_LIVE_BUILD_RUN_ROOT = "/mnt/shared/grml-live/runs"
GRML_LIVE_BUILD_STAGE_ROOT = "/var/tmp/grml-agent-build"

def build_iso(profile_name : String, progress : Proc(String, Nil)? = nil) : String
  validate_build_profile_name(profile_name)
  manifest = validate_profile(profile_name, progress)
  checkout_commit = ensure_grml_live_checkout_for_build(manifest.grml_live_ref, progress)
  verify_build_environment(manifest)

  timestamp = Time.utc.to_s("%Y%m%dT%H%M%SZ")
  nonce = Random.rand(0_i64..Int64::MAX).to_s(16)
  run_id = "#{timestamp}-#{nonce}"
  profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
  stage_directory = "#{GRML_LIVE_BUILD_STAGE_ROOT}/#{run_id}"
  config_directory = "#{stage_directory}/config"
  output_directory = "#{stage_directory}/output"
  temporary_directory = "#{stage_directory}/tmp"
  install_directory = "#{stage_directory}/chroot-install"
  shared_run_directory = "#{GRML_LIVE_BUILD_RUN_ROOT}/#{profile_name}/#{run_id}"
  shared_output_directory = "#{shared_run_directory}/output"

  report_build_profile_progress(progress, "Starting grml-live image-create")
  report_build_profile_progress(progress, "Profile: #{profile_name}")
  report_build_profile_progress(progress, "grml-live commit: #{checkout_commit}")
  report_build_profile_progress(progress, "Run ID: #{run_id}")
  report_build_profile_progress(progress, "Artifacts: #{shared_run_directory}")

  failure_exit_code = -1
  begin
    prepare_build_stage(
      profile_directory,
      stage_directory,
      config_directory,
      output_directory,
      temporary_directory,
      install_directory,
      shared_run_directory,
      shared_output_directory,
      progress
    )

    command = grml_live_build_command(manifest, config_directory, output_directory, temporary_directory, install_directory)
    started_at = Time.instant
    result = @interaction.execute_streaming(command, 6.hours) do |_stream, chunk|
      report_build_iso_output(progress, chunk)
    end
    failure_exit_code = result.exit_code

    preserve_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory)
    elapsed = Time.instant - started_at

    unless result.success?
      raise "grml-live image-create failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
    end

    verify_build_iso_output(shared_output_directory)
    mark_build_run(shared_run_directory, "COMPLETE", profile_name, run_id, checkout_commit, result.exit_code)
    report_build_profile_progress(progress, "grml-live image-create completed in #{elapsed.total_seconds.round(1)}s")
    report_build_profile_progress(progress, "ISO files: #{shared_output_directory}/grml_isos")
    report_build_profile_progress(progress, "Build logs: #{shared_output_directory}/grml_logs")
    shared_output_directory
  rescue ex
    preserve_partial_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory, progress)
    begin
      run_exists = @interaction.execute("test -d '#{shared_run_directory}'")
      if run_exists.success?
        building = @interaction.execute("test -s '#{shared_run_directory}/BUILDING'")
        if building.success?
          mark_build_run(shared_run_directory, "FAILED", profile_name, run_id, checkout_commit, failure_exit_code)
        end
      end
    rescue marker_error
      report_build_profile_progress(progress, "WARNING: could not mark failed build: #{marker_error.message}")
    end
    raise ex
  ensure
    cleanup_result = @interaction.execute("rm -rf '#{stage_directory}'", 2.minutes)
    unless cleanup_result.success?
      report_build_profile_progress(progress, "WARNING: could not remove temporary build directory #{stage_directory}")
    end
  end
end

private def ensure_grml_live_checkout_for_build(ref : String, progress : Proc(String, Nil)?) : String
  command = <<-SHELL
    set -eu
    if [ ! -x '#{GRML_LIVE_CHECKOUT}/grml-live' ]; then
      echo "grml-live is not installed; run prepare_build_environment PROFILE_NAME first" >&2
      exit 10
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
    raise "Could not select grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
end

private def verify_build_environment(manifest : LiveBuildManifest) : Nil
  minimum_bytes = manifest.classes.includes?("GRML_FULL") ? 4_i64 * 1024 * 1024 * 1024 : 2_i64 * 1024 * 1024 * 1024
  command = <<-SHELL
    set -eu
    test -x '#{GRML_LIVE_CHECKOUT}/grml-live'
    id '#{GRML_LIVE_BUILDER}' >/dev/null
    grep -q '^#{GRML_LIVE_BUILDER}:' /etc/subuid
    grep -q '^#{GRML_LIVE_BUILDER}:' /etc/subgid
    for program in dpkg mksquashfs mmdebstrap xorriso runuser unshare newuidmap newgidmap findmnt; do
      command -v "$program" >/dev/null || {
        echo "Required build program is missing: $program" >&2
        exit 11
      }
    done

    mount_options=$(findmnt -n -o OPTIONS -T /var/tmp)
    for option in nodev noexec nosuid; do
      case ",$mount_options," in
        *",$option,"*)
          echo "/var/tmp is mounted with $option; grml-live build output requires an executable, non-nodev, non-nosuid filesystem" >&2
          exit 12
          ;;
      esac
    done

    free_bytes=$(df -PB1 /var/tmp | awk 'NR == 2 {print $4}')
    if [ "$free_bytes" -lt #{minimum_bytes} ]; then
      echo "Insufficient free space under /var/tmp: $free_bytes bytes available, #{minimum_bytes} required" >&2
      exit 13
    fi

    runuser -u '#{GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
    SHELL
  result = @interaction.execute(command, 60.seconds)
  unless result.success?
    raise "grml-live build environment is not ready; run prepare_build_environment PROFILE_NAME (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end

private def prepare_build_stage(
  profile_directory : String,
  stage_directory : String,
  config_directory : String,
  output_directory : String,
  temporary_directory : String,
  install_directory : String,
  shared_run_directory : String,
  shared_output_directory : String,
  progress : Proc(String, Nil)?
) : Nil
  profile_config = "#{profile_directory}/grml-live/config"
  profile_install = "#{profile_directory}/grml-live/chroot-install"
  command = <<-SHELL
    set -eu
    checkout='#{GRML_LIVE_CHECKOUT}'
    profile_config='#{profile_config}'
    profile_install='#{profile_install}'
    stage='#{stage_directory}'
    config='#{config_directory}'
    output='#{output_directory}'
    tmp='#{temporary_directory}'
    install='#{install_directory}'
    run='#{shared_run_directory}'
    shared_output='#{shared_output_directory}'

    mkdir -p '#{GRML_LIVE_BUILD_STAGE_ROOT}' "$stage" "$config" "$output" "$tmp" "$run" "$shared_output"
    chmod 0755 '#{GRML_LIVE_BUILD_STAGE_ROOT}' "$stage" "$config" "$output" "$tmp"
    cp -a "$checkout/config/." "$config/"
    if [ -d "$profile_config" ]; then
      cp -a "$profile_config/." "$config/"
    fi
    if [ -d "$profile_install" ]; then
      mkdir -p "$install"
      cp -a "$profile_install/." "$install/"
      find "$install" -type d -exec chmod 0755 {} +
      find "$install" -type f -exec chmod a+r {} +
    fi

    find "$config" -type d -exec chmod 0755 {} +
    find "$config" -type f -exec chmod a+r {} +
    chown -R '#{GRML_LIVE_BUILDER}:#{GRML_LIVE_BUILDER}' "$stage"

    cp '#{profile_directory}/grml-live/build.yml' "$run/build.yml"
    printf 'run_id=%s\\nprofile=%s\\nstatus=BUILDING\\n' \
      '#{File.basename(stage_directory)}' '#{File.basename(profile_directory)}' > "$run/BUILDING"
    SHELL

  result = @interaction.execute(command, 5.minutes)
  unless result.success?
    raise "Could not stage grml-live profile (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  report_build_profile_progress(progress, "Merged upstream grml-live configuration with profile overrides")
end

private def grml_live_build_command(
  manifest : LiveBuildManifest,
  config_directory : String,
  output_directory : String,
  temporary_directory : String,
  install_directory : String
) : String
  args = [
    shell_quote("#{GRML_LIVE_CHECKOUT}/grml-live"),
    "image-create",
    "-F",
    "-D", shell_quote(config_directory),
    "-s", shell_quote(manifest.suite),
    "-c", shell_quote(manifest.classes_argument),
    "--hostname", shell_quote(manifest.hostname),
    "--username", shell_quote(manifest.username),
    "--distri-name", shell_quote(manifest.distri_name),
    "--distri-info", shell_quote(manifest.distri_info),
    "-g", shell_quote(manifest.grml_name),
    "-r", shell_quote(manifest.release_name),
    "-v", shell_quote(manifest.version),
    "--bootstrap-mirror-url", shell_quote(manifest.bootstrap_mirror_url),
  ]

  unless manifest.boot_options.empty?
    args << "--boot-options" << shell_quote(manifest.boot_options.join(" "))
  end
  args << "--secure-boot" if manifest.secure_boot
  args << "-R" unless manifest.release
  if iso_name = manifest.iso_name
    args << "-i" << shell_quote(iso_name)
  end
  if build_date = manifest.date
    args << "-d" << shell_quote(build_date)
  end
  args << "-I" << shell_quote(install_directory) if directory_exists_in_guest?(install_directory)
  args << shell_quote(output_directory)

  environment = [
    "TMPDIR=#{shell_quote(temporary_directory)}",
    "APT_PROXY='http://127.0.0.1:3142'",
  ]
  if epoch = manifest.source_date_epoch
    environment << "SOURCE_DATE_EPOCH=#{epoch}"
  end

  "set -eu; runuser -u '#{GRML_LIVE_BUILDER}' -- env #{environment.join(" ")} #{args.join(" ")}"
end

private def directory_exists_in_guest?(path : String) : Bool
  result = @interaction.execute("test -d '#{path}'")
  result.success?
end

private def preserve_partial_build_output(
  output_directory : String,
  profile_directory : String,
  shared_run_directory : String,
  shared_output_directory : String,
  progress : Proc(String, Nil)?
) : Nil
  preserve_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory)
rescue ex
  report_build_profile_progress(progress, "WARNING: could not preserve partial build output: #{ex.message}")
end

private def preserve_build_output(
  output_directory : String,
  profile_directory : String,
  shared_run_directory : String,
  shared_output_directory : String
) : Nil
  command = <<-SHELL
    set -eu
    mkdir -p '#{shared_output_directory}'
    if [ -d '#{output_directory}' ]; then
      cp -R --preserve=mode,timestamps --no-preserve=ownership '#{output_directory}/.' '#{shared_output_directory}/'
    fi
    cp '#{profile_directory}/grml-live/build.yml' '#{shared_run_directory}/build.yml'
    SHELL
  result = @interaction.execute(command, 10.minutes)
  unless result.success?
    raise "Could not preserve grml-live build output (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end

private def verify_build_iso_output(shared_output_directory : String) : Nil
  command = "find '#{shared_output_directory}/grml_isos' -maxdepth 1 -type f -name '*.iso' -print -quit | grep -q ."
  result = @interaction.execute(command)
  unless result.success?
    raise "grml-live returned success but no ISO file was found in #{shared_output_directory}/grml_isos"
  end
end

private def mark_build_run(
  shared_run_directory : String,
  state : String,
  profile_name : String,
  run_id : String,
  checkout_commit : String,
  exit_code : Int32
) : Nil
  command = <<-SHELL
    set -eu
    printf 'run_id=%s\\nprofile=%s\\nstatus=%s\\ngrml_live_commit=%s\\nexit_code=%s\\n' \
      '#{run_id}' '#{profile_name}' '#{state}' '#{checkout_commit}' '#{exit_code}' > '#{shared_run_directory}/#{state}'
    rm -f '#{shared_run_directory}/BUILDING'
    SHELL
  result = @interaction.execute(command)
  unless result.success?
    raise "Could not write grml-live build status '#{state}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
end

private def report_build_iso_output(progress : Proc(String, Nil)?, chunk : String) : Nil
  return if chunk.empty?
  if callback = progress
    callback.call(chunk)
  else
    Log.info { chunk }
  end
end
