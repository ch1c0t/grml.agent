private def build_environment_diagnostic_command(command : String, label : String) : String
  unless label.matches?(/\A[a-z0-9][a-z0-9-]*\z/)
    raise ArgumentError.new("Invalid build diagnostic label: #{label.inspect}")
  end
  script = build_environment_diagnostic_script(command)
  directory = "/var/log/grml-agent/build-environment"
  wrapper = [
    "set -eu", "mkdir -p #{directory}",
    "log_path=#{directory}/#{label}.log",
    "script_path=#{directory}/#{label}.sh",
    ": > \"$log_path\"",
    "printf '%s\\n' #{shell_quote(script)} > \"$script_path\"",
    "exec > >(tee -a \"$log_path\") 2> >(tee -a \"$log_path\" >&2)",
    "printf '[diagnostics] script: %s\\n[diagnostics] log: %s\\n' \"$script_path\" \"$log_path\"",
    "bash \"$script_path\"",
  ].join("\n")
  "/bin/bash -c #{shell_quote(wrapper)}"
end
