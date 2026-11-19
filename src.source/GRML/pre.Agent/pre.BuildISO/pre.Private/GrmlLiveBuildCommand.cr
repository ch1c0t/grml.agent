private def grml_live_build_command(
  manifest : LiveBuildManifest,
  config_directory : String,
  output_directory : String,
  temporary_directory : String,
  install_directory : String
) : String
  args = [
    shell_quote("#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live"),
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
  if wayback_date = manifest.wayback_date
    args << "-w" << shell_quote(wayback_date)
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

  "set -eu; runuser -u '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' -- env #{environment.join(" ")} #{args.join(" ")}"
end
