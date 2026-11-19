require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_composition_harness"

describe "profile application reports" do
  it "records a successful application through the agent API" do
    agent, root = ProfileCompositionSpecFixture.build
    begin
      ProfileCompositionSpecFixture.add(root, "rescue")
      agent.apply_profile("rescue")
      paths = Dir.glob(File.join(root, "profile-applications", "*", "report.json"))
      paths.size.should eq(1)
      report = JSON.parse(File.read(paths.first))
      report["status"].as_s.should eq("success")
      report["origin"].as_s.should eq("api")
      report["profiles"][0]["name"].as_s.should eq("rescue")
      report["operations"][0]["kind"].as_s.should eq("packages")
    ensure
      ProfileCompositionSpecFixture.remove(root)
    end
  end
end
