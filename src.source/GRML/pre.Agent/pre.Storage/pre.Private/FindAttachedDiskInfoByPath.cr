private def find_attached_disk_info_by_path(path : String) : JSON::Any?
  response = execute_qmp_checked("query-block", Hash(String, JSON::Any).new)
  records = response.as_h["return"]?.try(&.as_a)
  raise "QMP query-block returned no block-device list" unless records
  matches = records.compact_map do |item|
    inserted = item.as_h["inserted"]?
    attached_path = inserted.try { |block| block.as_h["file"]?.try(&.as_s) }
    inserted if attached_path && File.expand_path(attached_path) == File.expand_path(path)
  end
  raise "QEMU reports multiple devices for image: #{path}" if matches.size > 1
  matches.first?
end
