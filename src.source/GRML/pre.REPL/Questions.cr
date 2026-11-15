def focus? : Bool
  value = ENV.fetch(GRML::REPL::FOCUS_ENV, "true").strip.downcase
  case value
  when "1", "true", "yes", "on" then true
  when "0", "false", "no", "off" then false
  else raise ArgumentError.new("#{GRML::REPL::FOCUS_ENV} must be a boolean; got #{value.inspect}")
  end
end
