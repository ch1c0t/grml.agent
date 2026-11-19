private def shell_quote(value : String) : String
  "'" + value.gsub("'", "'\\''") + "'"
end
