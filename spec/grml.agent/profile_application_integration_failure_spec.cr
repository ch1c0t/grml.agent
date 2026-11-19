require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_composition_harness"

describe "failed profile application reports" do
  it "persists dependency resolution failures" do
    agent, root = ProfileCompositionSpecFixture.build
    begin
      ProfileCompositionSpecFixture.add(root, "first", "second\n")
      ProfileCompositionSpecFixture.add(root, "second", "first\n")
      expect_raises(ArgumentError, "Profile dependency cycle") { agent.apply_profile("first") }
      path = Dir.glob(File.join(root, "profile-applications", "*", "report.json")).first
      report = JSON.parse(File.read(path))
      report["status"].as_s.should eq("failed")
      report["error"].as_s.should contain("Profile dependency cycle")
    ensure
      ProfileCompositionSpecFixture.remove(root)
    end
  end
end
