def build_iso(profile_name : String, progress : Proc(String, Nil)? = nil) : String
  validate_build_profile_name(profile_name)
  manifest = validate_profile(profile_name, progress)
  checkout_commit = ensure_grml_live_checkout_for_build(manifest.grml_live_ref, progress)
  verify_build_environment(manifest)

  timestamp = Time.utc.to_s("%Y%m%dT%H%M%SZ")
  nonce = Random.rand(0_i64..Int64::MAX).to_s(16)
  run_id = "#{timestamp}-#{nonce}"
  profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
  stage_directory = "#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_STAGE_ROOT}/#{run_id}"
  config_directory = "#{stage_directory}/config"
  output_directory = "#{stage_directory}/output"
  temporary_directory = "#{stage_directory}/tmp"
  install_directory = "#{stage_directory}/chroot-install"
  shared_run_directory = "#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_RUN_ROOT}/#{profile_name}/#{run_id}"
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
