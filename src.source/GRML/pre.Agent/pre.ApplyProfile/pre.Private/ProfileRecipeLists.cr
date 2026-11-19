private def expand_profile_recipe_list(root : String, path : String,
                                       visiting : Array(String), recipes : Array(String)) : Nil
  real = File.real_path(path)
  if visiting.includes?(real)
    raise ArgumentError.new("Mitamae recipe list cycle: #{(visiting + [real]).join(" -> ")}")
  end
  visiting << real
  File.each_line(path) do |line|
    entry = line.sub(/#.*/, "").strip
    expand_profile_mitamae_recipe(root, entry, visiting, recipes) unless entry.empty?
  end
  visiting.pop
end
