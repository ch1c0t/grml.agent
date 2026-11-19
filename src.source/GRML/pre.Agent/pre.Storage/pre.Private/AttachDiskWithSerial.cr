private def attach_disk_with_serial(
  path : String,
  format : String,
  suffix : String? = nil,
  serial : String? = nil
) : NamedTuple(device_id: String, serial: String)
  validate_disk_format(format)
  expanded_path = File.expand_path(path)
  raise "Disk image does not exist: #{expanded_path}" unless File.file?(expanded_path)

  identifier = suffix || Random.rand(1..Int32::MAX).to_s
  unless identifier.matches?(/\A[A-Za-z0-9_-]+\z/)
    raise ArgumentError.new("Invalid QEMU disk identifier: #{identifier.inspect}")
  end
  device_serial = serial || "grml-#{identifier}"
  unless device_serial.matches?(/\A[A-Za-z0-9._-]{1,20}\z/)
    raise ArgumentError.new("Invalid QEMU disk serial: #{device_serial.inspect}")
  end

  file_node = "grml_disk_file_#{identifier}"
  disk_node = "grml_disk_#{identifier}"
  device_id = "grml_virtio_disk_#{identifier}"

  file_arguments = JSON.parse({
    "driver" => "file",
    "filename" => expanded_path,
    "node-name" => file_node,
    "auto-read-only" => true
  }.to_json).as_h
  format_arguments = JSON.parse({
    "driver" => format,
    "file" => file_node,
    "node-name" => disk_node
  }.to_json).as_h

  execute_qmp_checked("blockdev-add", file_arguments)
  begin
    execute_qmp_checked("blockdev-add", format_arguments)
    execute_qmp_checked("device_add", JSON.parse({
      "driver" => "virtio-blk-pci",
      "drive" => disk_node,
      "id" => device_id,
      "serial" => device_serial
    }.to_json).as_h)
  rescue ex
    begin
      execute_qmp_checked("blockdev-del", {"node-name" => JSON::Any.new(disk_node)})
    rescue
    end
    begin
      execute_qmp_checked("blockdev-del", {"node-name" => JSON::Any.new(file_node)})
    rescue
    end
    raise ex
  end

  {device_id: device_id, serial: device_serial}
end
