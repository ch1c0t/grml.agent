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
    checkout='#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}'
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
    chown -R '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' "$stage"

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
