private def find_attached_disk_path(device_id : String) : String?
  inserted = find_attached_disk_info(device_id)
  return unless inserted
  path = inserted.as_h["file"]?.try(&.as_s)
  raise "QMP reports #{device_id} attached without a backing-file path" unless path
  path
end
