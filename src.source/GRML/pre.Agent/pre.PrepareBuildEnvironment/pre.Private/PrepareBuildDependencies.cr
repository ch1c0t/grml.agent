private def prepare_build_dependencies(packages : Array(String), progress) : Nil
  all_packages = (GRML_LIVE_BUILDER_PACKAGES + packages).uniq
  report_build_environment_stage(3, "Installing grml-live build dependencies", progress) do
    report_build_profile_progress(progress, "Builder packages: #{all_packages.size}")
    run_build_environment_command(build_dependencies_command(all_packages), 45.minutes, progress, "dependencies")
  end
end
