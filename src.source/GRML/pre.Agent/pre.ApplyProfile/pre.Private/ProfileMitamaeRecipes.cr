private def profile_mitamae_recipes(profile_name : String) : Array(String)
  root = File.expand_path(File.join(@vm.shared_path, "profiles", profile_name))
  manifest = File.join(root, "mitamae-recipes.txt")
  return [] of String unless File.file?(manifest)
  unless File.realpath(manifest).starts_with?("#{File.realpath(root)}/")
    raise ArgumentError.new("Mitamae recipe manifest escapes profile: #{manifest}")
  end

  recipes = [] of String
  File.each_line(manifest) do |line|
    entry = line.sub(/#.*/, "").strip
    expand_profile_mitamae_recipe(root, entry, [] of String, recipes) unless entry.empty?
  end
  recipes
end
