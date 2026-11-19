private def apply_profile_with_report(profile_name : String, verify_cache : Bool,
                                       progress : Proc(String, Nil)?,
                                       report : ProfileApplicationReport) : Nil
  recorded = ->(chunk : String) { report.append_output(chunk); forward_profile_progress(progress, chunk) }
  begin
    apply_profile_steps(profile_name, verify_cache, recorded, report)
    report.finish("success")
  rescue exception
    report.finish("failed", exception.to_s)
    raise
  end
end

private def forward_profile_progress(progress : Proc(String, Nil)?, chunk : String) : Nil
  progress ? progress.call(chunk) : Log.info { chunk }
end
