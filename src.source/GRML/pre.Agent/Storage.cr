DISK_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
DISK_SIZE_PATTERN = /\A[1-9][0-9]*(?:[KMGTP])?\z/i
DISK_FORMATS = ["qcow2", "raw"]

def create_disk(name : String, size : String, format : String = "qcow2") : String
  path = create_disk_image(name, size, format)

  begin
    attach_disk(path, format)
  rescue ex
    File.delete(path) if File.exists?(path)
    raise ex
  end

  path
end

def create_ext4_disk(
  name : String,
  size : String,
  mountpoint : String? = nil,
  format : String = "qcow2"
) : String
  validate_disk_name(name)
  validate_disk_format(format)
  guest_mountpoint = validate_guest_mountpoint(mountpoint || "/mnt/#{name}")

  path = create_disk_image(name, size, format)

  attached = begin
    attach_disk_with_serial(path, format)
  rescue ex
    File.delete(path) if File.exists?(path)
    raise ex
  end

  begin
    result = @interaction.execute(
      ext4_provisioning_command(attached[:serial], guest_mountpoint),
      2.minutes
    )

    unless result.success?
      details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
      message = "Guest provisioning command exited with status #{result.exit_code}"
      message += ":\n#{details}" unless details.empty?
      raise message
    end
  rescue ex
    raise "Disk image #{path} remains attached as #{attached[:device_id]}, but guest partitioning, ext4 formatting, or mounting failed: #{ex.message}"
  end

  "#{path} (ext4 mounted at #{guest_mountpoint})"
end

def attach_disk(path : String, format : String = "qcow2") : String
  attach_disk_with_serial(path, format)[:device_id]
end

private def validate_disk_name(name : String) : Nil
  unless name.matches?(DISK_NAME_PATTERN)
    raise ArgumentError.new("Invalid disk name: #{name.inspect}")
  end
end

private def create_disk_image(name : String, size : String, format : String) : String
  validate_disk_name(name)

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

  path
end

private def attach_disk_with_serial(
  path : String,
  format : String
) : NamedTuple(device_id: String, serial: String)
  validate_disk_format(format)
  expanded_path = File.expand_path(path)
  raise "Disk image does not exist: #{expanded_path}" unless File.file?(expanded_path)

  suffix = Random.rand(1..Int32::MAX)
  file_node = "grml_disk_file_#{suffix}"
  disk_node = "grml_disk_#{suffix}"
  device_id = "grml_virtio_disk_#{suffix}"
  serial = "grml-#{suffix}"

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
      "serial" => serial
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

  {device_id: device_id, serial: serial}
end

private def validate_guest_mountpoint(path : String) : String
  unless path.starts_with?("/") && path != "/" && !path.split("/").any? { |part| part == "." || part == ".." }
    raise ArgumentError.new("Mount point must be an absolute guest path without '.' or '..' components: #{path.inspect}")
  end
  path
end

private def ext4_provisioning_command(serial : String, mountpoint : String) : String
  disk = shell_quote("/dev/disk/by-id/virtio-#{serial}")
  target = shell_quote(mountpoint)

  <<-SCRIPT
    set -eu
    disk=#{disk}
    partition="$disk-part1"
    mountpoint=#{target}

    for attempt in $(seq 1 50); do
      [ -b "$disk" ] && break
      sleep 0.1
    done
    if [ ! -b "$disk" ]; then
      echo "Guest block device did not appear: $disk" >&2
      exit 1
    fi

    if mountpoint -q "$mountpoint"; then
      echo "Guest mount point is already in use: $mountpoint" >&2
      exit 1
    fi

    printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
    blockdev --rereadpt "$disk"
    udevadm settle

    for attempt in $(seq 1 50); do
      [ -b "$partition" ] && break
      sleep 0.1
    done
    if [ ! -b "$partition" ]; then
      echo "Guest partition did not appear: $partition" >&2
      exit 1
    fi

    mkfs.ext4 -F "$partition"
    mkdir -p "$mountpoint"
    mount -t ext4 "$partition" "$mountpoint"
    findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
    printf 'Mounted %s on %s as ext4\\n' "$partition" "$mountpoint"
  SCRIPT
end

private def shell_quote(value : String) : String
  "'" + value.gsub("'", "'\\''") + "'"
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
