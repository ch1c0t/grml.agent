private def execute_profile_mitamae_recipes(profile_name : String, recipes : Array(String),
                                              progress : Proc(String, Nil)?) : Nil
  recipes.each do |relative|
    recipe = File.join(DEBIAN_PROFILE_DIRECTORY, profile_name, relative)
    node = File.join(DEBIAN_PROFILE_DIRECTORY, profile_name, "mitamae-node.yml")
    command = mitamae_recipe_command(recipe, node)
    report_profile_progress(progress, "Applying Mitamae recipe '#{relative}' from profile '#{profile_name}'")
    result = @interaction.execute_streaming(command, 30.minutes) do |_stream, chunk|
      report_profile_output(progress, chunk)
    end
    unless result.success?
      raise "Mitamae recipe '#{relative}' in profile '#{profile_name}' failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
    end
  end
end

private def mitamae_recipe_command(recipe : String, node : String) : String
  recipe = profile_shell_quote(recipe)
  node = profile_shell_quote(node)
  <<-SHELL
    set -eu
    command -v mitamae >/dev/null 2>&1 || { echo "mitamae is not installed in the guest" >&2; exit 127; }
    if [ -f #{node} ]; then
      mitamae local --node-yaml #{node} #{recipe}
    elif [ -f /root/.config/recipes/node.yml ]; then
      mitamae local --node-yaml /root/.config/recipes/node.yml #{recipe}
    else
      mitamae local #{recipe}
    fi
    SHELL
end
