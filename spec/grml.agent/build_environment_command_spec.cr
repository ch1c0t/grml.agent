require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBuildCommandFakeInteraction
  def execute_streaming(command, timeout, &block : Symbol, String ->)
    yield :stderr, "bash: syntax error near unexpected token"
    QEMU::CommandResult.new(2, "", "")
  end
end

class GRMLBuildCommandHarness
  include GRML::Agent::Storage
  include GRML::Agent::PrepareBuildEnvironment
  def initialize(@interaction : GRMLBuildCommandFakeInteraction); end
  def run : Nil
    run_build_environment_command("false", 1.second, nil, "builder-account")
  end
  def python_script : String; build_subordinate_id_script; end
end

describe "grml-live preparation diagnostics" do
  it "preserves streamed stderr when the command result has empty buffers" do
    error = expect_raises(Exception) { GRMLBuildCommandHarness.new(GRMLBuildCommandFakeInteraction.new).run }
    error.to_s.should contain("syntax error")
    error.to_s.should contain("builder-account.log")
  end
  it "generates syntactically valid Python without a nested here-document" do
    script = GRMLBuildCommandHarness.new(GRMLBuildCommandFakeInteraction.new).python_script
    result = Process.run("python3", ["-c", "import ast,sys; ast.parse(sys.stdin.read())"],
      input: IO::Memory.new(script), error: IO::Memory.new)
    result.success?.should be_true
  end
end
