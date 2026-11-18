private def find_attached_disk_info(device_id : String) : JSON::Any?
  response = execute_qmp_checked("query-block", Hash(String, JSON::Any).new)
  records = response.as_h["return"]?.try(&.as_a)
  raise "QMP query-block returned no block-device list" unless records
  record = records.find { |item| item.as_h["device"]?.try(&.as_s) == device_id }
  return unless record
  inserted = record.as_h["inserted"]?
  raise "QMP reports #{device_id} attached without backing-file details" unless inserted
  inserted
end
