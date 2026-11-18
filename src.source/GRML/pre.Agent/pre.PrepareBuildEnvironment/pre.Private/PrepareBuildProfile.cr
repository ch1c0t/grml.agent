private def prepare_build_profile(profile_name, progress)
  report_build_environment_stage(1, "Validating build profile", progress) do
    directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
    verify_profile_tree(directory)
    packages = read_builder_packages(directory)
    manifest = validate_profile(profile_name, progress)
    {manifest: manifest, packages: packages}
  end
end
