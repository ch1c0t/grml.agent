private def report_build_environment_stage(
  index : Int32,
  title : String,
  progress : Proc(String, Nil)?,
  &block : -> Nil
) : Nil
  label = "[#{index}/4] #{title}"
  started_at = Time.instant
  report_build_profile_progress(progress, "#{label} ...")
  begin
    yield
  rescue ex
    elapsed = Time.instant - started_at
    report_build_profile_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
    raise "Failed during #{title}: #{ex.message}"
  end
  elapsed = Time.instant - started_at
  report_build_profile_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
end
