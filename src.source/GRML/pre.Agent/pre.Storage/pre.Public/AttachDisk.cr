def attach_disk(path : String, format : String = "qcow2") : String
  attach_disk_with_serial(path, format)[:device_id]
end
