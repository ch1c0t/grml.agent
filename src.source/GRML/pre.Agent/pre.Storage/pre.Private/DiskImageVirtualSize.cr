private def disk_image_virtual_size(json : String) : Int64
  JSON.parse(json).as_h["virtual-size"].as_i64
rescue ex
  raise "Invalid disk image virtual-size JSON: #{ex.message}"
end
