private def preserve_partial_build_output(
  output_directory : String,
  profile_directory : String,
  shared_run_directory : String,
  shared_output_directory : String,
  progress : Proc(String, Nil)?
) : Nil
  preserve_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory)
rescue ex
  report_build_profile_progress(progress, "WARNING: could not preserve partial build output: #{ex.message}")
end
