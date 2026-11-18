private def find_named_block_node_path(node_name : String) : String?
  node = find_named_block_node(node_name)
  return unless node
  path = node.as_h["file"]?.try(&.as_s)
  raise "QMP reports #{node_name} without a backing-file path" unless path
  path
end
