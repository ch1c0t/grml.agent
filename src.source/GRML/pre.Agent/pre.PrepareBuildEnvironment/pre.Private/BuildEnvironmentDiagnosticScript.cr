private def build_environment_diagnostic_script(command : String) : String
  [
    "set -Eeuo pipefail",
    "trap 'status=$?; printf \"[command failed] exit=%s line=%s command=%s\\n\" \"$status\" \"$LINENO\" \"$BASH_COMMAND\" >&2' ERR",
    "set -x",
    command,
  ].join("\n")
end
