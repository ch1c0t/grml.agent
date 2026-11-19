private def ensure_build_workspace(progress : Proc(String, Nil)?) : Nil
  report_build_environment_stage(5, "Provisioning persistent ext4 build workspace", progress) do
    disk = ensure_ext4_disk(
      GRML_LIVE_BUILD_DISK_NAME, GRML_LIVE_BUILD_DISK_SIZE,
      GRML_LIVE_BUILD_WORKSPACE, "qcow2", progress
    )
    report_build_profile_progress(progress, "Persistent build workspace: #{disk}")
  end
end
