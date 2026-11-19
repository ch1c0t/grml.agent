require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_executable_harness"
require "../support/profile_executable_fixture"

describe "profile host executables" do
  it "prefers an executable found on the host" do
    agent, root = ProfileExecutableSpecFixture.build("/host/mitamae")
    begin
      agent.apply_profile("rescue")
      agent.copied.should eq([{"/host/mitamae", "/usr/local/bin/mitamae"}])
      agent.downloads.should be_empty
    ensure
      ProfileExecutableSpecFixture.remove(root)
    end
  end

  it "downloads the configured fallback when the host executable is missing" do
    agent, root = ProfileExecutableSpecFixture.build(nil)
    begin
      agent.apply_profile("rescue")
      agent.downloads.should eq(["https://example.invalid/mitamae"])
      agent.copied.should eq([{File.join(root, "downloaded-mitamae"), "/usr/local/bin/mitamae"}])
      File.exists?(File.join(root, "downloaded-mitamae")).should be_false
    ensure
      ProfileExecutableSpecFixture.remove(root)
    end
  end
end
