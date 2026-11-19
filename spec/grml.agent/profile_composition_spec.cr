require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_composition_harness"

describe "profile composition" do
  it "applies dependencies in order and only once across shared dependency paths" do
    agent, root = ProfileCompositionSpecFixture.build
    begin
      ProfileCompositionSpecFixture.add(root, "base")
      ProfileCompositionSpecFixture.add(root, "foundation", "base\n")
      ProfileCompositionSpecFixture.add(root, "tools", "base\n")
      ProfileCompositionSpecFixture.add(root, "development", "foundation\ntools\n")
      agent.apply_profile("development")
      agent.applied_profiles.should eq(["base", "foundation", "tools", "development"])
    ensure
      ProfileCompositionSpecFixture.remove(root)
    end
  end

  it "rejects dependency cycles before applying any profile" do
    agent, root = ProfileCompositionSpecFixture.build
    begin
      ProfileCompositionSpecFixture.add(root, "first", "second\n")
      ProfileCompositionSpecFixture.add(root, "second", "first\n")
      expect_raises(ArgumentError, "Profile dependency cycle") { agent.apply_profile("first") }
      agent.applied_profiles.should be_empty
    ensure
      ProfileCompositionSpecFixture.remove(root)
    end
  end
end
