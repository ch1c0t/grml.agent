private def expand_profile_mitamae_recipe(root : String, name : String,
                                          visiting : Array(String), recipes : Array(String)) : Nil
  path = File.expand_path(name, root)
  unless path.starts_with?("#{root}/")
    raise ArgumentError.new("Mitamae recipe path must stay inside profile: #{name.inspect}")
  end
  path = File.join(path, "default.rb") if Dir.exists?(path)
  raise ArgumentError.new("Mitamae recipe not found: #{path}") unless File.file?(path)
  real = File.real_path(path)
  raise ArgumentError.new("Mitamae recipe escapes profile: #{name.inspect}") unless real.starts_with?("#{File.real_path(root)}/")
  relative = path.sub("#{root}/", "")
  expand_profile_recipe_file(root, path, relative, visiting, recipes)
end

private def expand_profile_recipe_file(root : String, path : String, relative : String,
                                       visiting : Array(String), recipes : Array(String)) : Nil
  case File.extname(path)
  when ".rb"   then recipes << relative
  when ".list" then expand_profile_recipe_list(root, path, visiting, recipes)
  else raise ArgumentError.new("Mitamae recipe must be a .rb file, directory, or .list: #{path}")
  end
end
