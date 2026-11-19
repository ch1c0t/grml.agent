private def storage_diagnostics_payload(path : String, node_name : String) : String
  JSON.parse({
    "timestamp_utc" => Time.utc.to_s, "image_path" => path,
    "expected_node_name" => node_name,
    "vm" => {"running" => @vm.running?, "display" => @vm.display,
      "iso_path" => @vm.iso_path, "monitor_path" => @vm.monitor_path,
      "monitor_socket_exists" => File.exists?(@vm.monitor_path)},
    "qmp" => storage_qmp_diagnostics,
    "host" => storage_host_diagnostics(path)
  }.to_json).to_json
end
