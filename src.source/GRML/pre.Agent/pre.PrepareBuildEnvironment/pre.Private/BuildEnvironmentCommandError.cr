private def build_environment_command_error(label, exit_code, stdout, stderr) : String
  details = ["stderr:\n#{stderr}", "stdout:\n#{stdout}"].reject { |item| item.ends_with?(":\n") }
  details = ["No output was captured; inspect the persistent diagnostic log."] if details.empty?
  base = "/var/log/grml-agent/build-environment/#{label}"
  "Build environment command '#{label}' failed (exit=#{exit_code}):\n#{details.join("\n")}\nScript: #{base}.sh\nLog: #{base}.log"
end
