private def provision_ext4_disk(name, mountpoint, path, progress) : Nil
  report_storage_progress(progress, "Waiting for guest disk and preparing ext4 workspace")
  result = @interaction.execute_streaming(ensure_ext4_provisioning_command(name, mountpoint), 2.minutes) do |_stream, chunk|
    report_storage_output(progress, chunk)
  end
  raise_ext4_disk_provisioning_error(result, path) unless result.success?
  report_storage_progress(progress, "Guest ext4 workspace is mounted and verified")
end
