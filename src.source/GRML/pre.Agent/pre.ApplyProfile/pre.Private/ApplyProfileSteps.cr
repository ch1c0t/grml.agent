private def apply_profile_steps(name : String, verify : Bool, progress : Proc(String, Nil),
                                report : ProfileApplicationReport) : Nil
  profiles = profile_application_order(name).map do |profile_name|
    record = report.add_profile(profile_name, [] of String, [] of String, [] of String)
    packages = read_profile_packages(profile_name, progress)
    executables = profile_host_executables(profile_name)
    recipes = profile_mitamae_recipes(profile_name)
    record.packages, record.host_executables, record.recipes = packages, executables.map(&.[0]), recipes
    report.persist
    {profile_name, packages, executables, recipes, record}
  end
  profiles.each { |profile| apply_profile_steps_for(profile, progress, report) }
  return unless verify
  has_packages = profiles.any? { |profile| !profile[1].empty? }
  report.run_operation(nil, "cache_verification", "hello") do |_operation|
    verify_profile_cache(name, has_packages, verify, progress)
  end
end
