private def report_profile_output(progress : Proc(String, Nil)?, chunk : String) : Nil
  return if chunk.empty?
  if callback = progress
    callback.call(chunk)
  else
    Log.info { chunk }
  end
end

private def report_profile_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call("#{message}\n")
  else
    Log.info { message }
  end
end
