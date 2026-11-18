private def report_build_environment_output(progress : Proc(String, Nil)?, chunk : String) : Nil
  return if chunk.empty?
  if callback = progress
    callback.call(chunk)
  else
    Log.info { chunk }
  end
end
