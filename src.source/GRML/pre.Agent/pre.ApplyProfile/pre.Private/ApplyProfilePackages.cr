private def apply_profile_packages(profile_name : String, packages : Array(String),
                                    verify_cache : Bool, progress : Proc(String, Nil)?) : Nil
  if packages.empty?
    message = "Profile '#{profile_name}' contains no packages"
    verify_cache ? report_profile_progress(progress, "#{message}; preparing cache for verification") :
      report_profile_progress(progress, "#{message}; skipping APT cache preparation")
    prepare_deb_cache(progress) if verify_cache
  else
    install_profile_packages(profile_name, packages, progress)
  end
  if verify_cache
    report_profile_progress(progress, "Verifying shared Debian package cache after applying profile '#{profile_name}'")
    verify_deb_cache("hello", progress)
  end
end
