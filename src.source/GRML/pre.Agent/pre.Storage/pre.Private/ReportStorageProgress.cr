private def report_storage_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call("#{message}\n")
  else
    Log.info { message }
  end
end
