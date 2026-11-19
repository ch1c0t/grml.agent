require "spec"
require "../../src/logger"
require "../../src/grml"

class FakeExecutableCopyAgent
  getter copied = [] of Tuple(String, String)
  def copy_executable_to_guest(source : String, destination : String) : Nil
    @copied << {source, destination}
  end
end

describe "copy_executable" do
  it "copies the host path to the requested guest path" do
    agent = FakeExecutableCopyAgent.new
    result = GRML::REPL.copy_executable(agent, ["/usr/local/bin/mitamae", "/usr/local/bin/mitamae"])
    result.should contain("mode 0755")
    agent.copied.should eq([{"/usr/local/bin/mitamae", "/usr/local/bin/mitamae"}])
  end
  it "requires both host and guest paths" do
    expect_raises(ArgumentError, "Usage: copy_executable") { GRML::REPL.copy_executable(FakeExecutableCopyAgent.new, [] of String) }
  end
end
