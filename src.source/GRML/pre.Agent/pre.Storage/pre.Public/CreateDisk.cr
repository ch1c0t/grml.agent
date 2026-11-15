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
