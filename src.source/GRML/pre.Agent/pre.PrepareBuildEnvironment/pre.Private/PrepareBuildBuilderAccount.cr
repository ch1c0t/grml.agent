private def prepare_build_builder_account(progress : Proc(String, Nil)?) : Nil
  report_build_environment_stage(4, "Preparing unprivileged builder account and UID/GID mappings", progress) do
    run_build_environment_command(build_builder_account_command, 60.seconds, progress)
  end
end
