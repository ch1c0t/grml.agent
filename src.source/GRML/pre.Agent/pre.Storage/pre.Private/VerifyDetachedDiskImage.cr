private def verify_detached_disk_image(path, format, size, node_name, progress) : Nil
  verify_disk_image_size(path, format, size)
rescue ex
  begin
    report = write_storage_diagnostics(path, node_name)
    report_storage_progress(progress, "Storage diagnostics written: #{report}")
  rescue diagnostic_error
    raise "#{ex.message}\nCould not write storage diagnostics: #{diagnostic_error.message}"
  end
  raise "#{ex.message}\nStorage diagnostics: #{report}"
end
