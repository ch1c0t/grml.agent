private def capture_storage_qmp(command : String) : JSON::Any
  @vm.execute_qmp(command)
rescue ex
  JSON.parse({"error" => ex.message}.to_json)
end
