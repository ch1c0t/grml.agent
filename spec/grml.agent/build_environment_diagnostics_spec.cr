require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBuildDiagnosticsHarness
  include GRML::Agent::Storage
  include GRML::Agent::PrepareBuildEnvironment
  def python_command : String
    build_subordinate_id_command
  end
  def diagnostic_command : String
    build_environment_diagnostic_command("false", "builder-account")
  end
end

describe "grml-live build diagnostics" do
  it "runs the subordinate-ID script with python -c instead of a nested here-document" do
    command = GRMLBuildDiagnosticsHarness.new.python_command
    command.should start_with("python3 -c ")
    command.should contain("ensure_range")
    command.should contain("/etc/subuid")
    command.should contain("/etc/subgid")
    command.should_not contain("<<'PY'")
  end
  it "stores a traced shell script and a persistent stdout/stderr transcript" do
    command = GRMLBuildDiagnosticsHarness.new.diagnostic_command
    command.should contain("set -x")
    command.should contain("BASH_COMMAND")
    command.should contain("/var/log/grml-agent/build-environment/builder-account.log")
  end
end
