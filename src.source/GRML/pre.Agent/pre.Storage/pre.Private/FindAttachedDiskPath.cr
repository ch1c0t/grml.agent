private def find_attached_disk_path(device_id : String) : String?
  response = execute_qmp_checked("query-block", Hash(String, JSON::Any).new)
  records = response.as_h["return"]?.try(&.as_a)
  raise "QMP query-block returned no block-device list" unless records

  records.each do |record|
    block = record.as_h
    next unless block["device"]?.try(&.as_s) == device_id

    inserted = block["inserted"]?.try(&.as_h)
    raise "QMP reports #{device_id} attached without backing-file details" unless inserted
    path = inserted["file"]?.try(&.as_s)
    raise "QMP reports #{device_id} attached without a backing-file path" unless path
    return path
  end

  nil
end
