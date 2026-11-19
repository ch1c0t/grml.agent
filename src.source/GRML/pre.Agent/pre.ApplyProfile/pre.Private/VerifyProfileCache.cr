private def verify_profile_cache(profile_name : String, has_packages : Bool,
                                 verify_cache : Bool, progress : Proc(String, Nil)?) : Nil
  return unless verify_cache
  prepare_deb_cache(progress) unless has_packages
  report_profile_progress(progress, "Verifying shared Debian package cache after applying profile '#{profile_name}'")
  verify_deb_cache("hello", progress)
end
