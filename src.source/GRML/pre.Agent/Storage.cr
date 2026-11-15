DISK_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
DISK_SIZE_PATTERN = /\A[1-9][0-9]*(?:[KMGTP])?\z/i
DISK_FORMATS = ["qcow2", "raw"]

def create_disk(name : String, size : String, format : String = "qcow2") : String
  unless name.matches?(DISK_NAME_PATTERN)
    raise ArgumentError.new("Invalid disk name: #{name.inspect}")
  end
  unless size.matches?(DISK_SIZE_PATTERN)
    raise ArgumentError.new("Invalid disk size: #{size.inspect}; use e.g. 10G")
  end
  validate_disk_format(format)

  directory = File.expand_path("./disks")
  Dir.mkdir_p(directory)
  path = File.join(directory, "#{name}.#{format}")
  raise "Disk already exists: #{path}" if File.exists?(path)

  output = IO::Memory.new
  error = IO::Memory.new
  result = Process.run("qemu-img", ["create", "-f", format, path, size], output: output, error: error)
  unless result.success?
    raise "qemu-img failed (#{result.exit_code}): #{error.to_s.strip}"
  end

  begin
    attach_disk(path, format)
  rescue ex
    File.delete(path) if File.exists?(path)
    raise ex
  end

  path
end

def attach_disk(path : String, format : String = "qcow2") : String
  validate_disk_format(format)
  expanded_path = File.expand_path(path)
  raise "Disk image does not exist: #{expanded_path}" unless File.file?(expanded_path)

  suffix = Random.rand(1_000_000)
  file_node = "grml_disk_file_#{suffix}"
  disk_node = "grml_disk_#{suffix}"
  device_id = "grml_virtio_disk_#{suffix}"

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
      "id" => device_id
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

  device_id
end

private def validate_disk_format(format : String) : Nil
  unless DISK_FORMATS.includes?(format)
    raise ArgumentError.new("Unsupported disk format #{format.inspect}; choose qcow2 or raw")
  end
end

private def execute_qmp_checked(command : String, arguments : Hash(String, JSON::Any)) : JSON::Any
  response = @vm.execute_qmp(command, arguments)
  if error = response.as_h["error"]?
    raise "QMP #{command} failed: #{error}"
  end
  response
end
