private def verify_attached_disk_image(inserted : JSON::Any, path : String, format : String, size : String) : Nil
  details = inserted.as_h
  attached_path = details["file"]?.try(&.as_s)
  raise "QMP attachment has no backing-file path" unless attached_path
  raise "QEMU disk attachment path mismatch: #{attached_path}" unless File.expand_path(attached_path) == path
  image = details["image"]?
  raise "QMP attachment has no image metadata" unless image
  actual_format = image.as_h["format"]?.try(&.as_s)
  raise "Attached disk format mismatch: #{actual_format.inspect}, expected #{format}" unless actual_format == format
  actual_bytes = disk_image_virtual_size(image.to_json)
  expected_bytes = expected_disk_image_size(size)
  raise "Attached disk is too small: #{actual_bytes} bytes, #{expected_bytes} required" if actual_bytes < expected_bytes
end
