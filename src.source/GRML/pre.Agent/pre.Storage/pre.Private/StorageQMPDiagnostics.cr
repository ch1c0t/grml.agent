private def storage_qmp_diagnostics : JSON::Any
  JSON.parse({
    "query-named-block-nodes" => capture_storage_qmp("query-named-block-nodes"),
    "query-block" => capture_storage_qmp("query-block"),
    "query-status" => capture_storage_qmp("query-status"),
    "query-version" => capture_storage_qmp("query-version")
  }.to_json)
end
