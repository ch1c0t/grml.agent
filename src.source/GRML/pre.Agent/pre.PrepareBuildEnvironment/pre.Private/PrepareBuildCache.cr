private def prepare_build_cache(progress) : Nil
  report_build_environment_stage(2, "Preparing shared Debian package cache", progress) do
    prepare_deb_cache(progress)
  end
end
