def prepare_build_environment(profile_name : String, progress : Proc(String, Nil)? = nil) : Nil
  validate_build_profile_name(profile_name)
  report_build_profile_progress(progress, "Preparing grml-live build environment for '#{profile_name}'")
  profile = prepare_build_profile(profile_name, progress)
  prepare_build_cache(progress)
  prepare_build_dependencies(profile[:packages], progress)
  prepare_build_builder_account(progress)
  ensure_build_workspace(progress)
  checkout_grml_live(profile[:manifest].grml_live_ref, progress)
  report_build_profile_progress(progress, "grml-live build environment is ready")
end
