private def directory_exists_in_guest?(path : String) : Bool
  result = @interaction.execute("test -d '#{path}'")
  result.success?
end
