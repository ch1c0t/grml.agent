private def apply_profile_steps_for(profile : Tuple(String, Array(String), Array(Tuple(String, String)), Array(String), ProfileApplicationProfile),
                                    progress : Proc(String, Nil), report : ProfileApplicationReport) : Nil
  name, packages, executables, recipes, record = profile
  begin
    if packages.empty?
      report.skip_operation(name, "packages", "packages.txt")
      apply_profile_packages(name, packages, progress)
    else
      report.run_operation(name, "packages", packages.join(" ")) { |_op| apply_profile_packages(name, packages, progress) }
    end
    executables.each do |entry|
      report.run_operation(name, "host_executable", entry[0]) { |_op| install_profile_host_executables([entry], progress) }
    end
    recipes.each do |recipe|
      report.run_operation(name, "mitamae_recipe", recipe) { |op| execute_profile_mitamae_recipes(name, [recipe], progress, op) }
    end
    report.finish_profile(record, "success")
  rescue
    report.finish_profile(record, "failed")
    raise
  end
end
