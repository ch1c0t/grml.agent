private def profile_shell_quote(value : String) : String
  "'" + value.gsub("'", "'\\''") + "'"
end
