private def apply_profile_packages(profile_name : String, packages : Array(String),
                                    progress : Proc(String, Nil)?) : Nil
  if packages.empty?
    report_profile_progress(progress, "Profile '#{profile_name}' contains no packages; skipping package installation")
  else
    install_profile_packages(profile_name, packages, progress)
  end
end
