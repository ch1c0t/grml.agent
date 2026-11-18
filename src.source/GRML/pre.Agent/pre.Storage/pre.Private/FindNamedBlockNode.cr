private def find_named_block_node(node_name : String) : JSON::Any?
  response = execute_qmp_checked("query-named-block-nodes", Hash(String, JSON::Any).new)
  records = response.as_h["return"]?.try(&.as_a)
  raise "QMP query-named-block-nodes returned no node list" unless records
  records.find { |item| item.as_h["node-name"]?.try(&.as_s) == node_name }
end
