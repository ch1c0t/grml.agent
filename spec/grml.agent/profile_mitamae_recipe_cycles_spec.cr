require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_mitamae_harness"
require "../support/profile_mitamae_fixture"

describe "Mitamae recipe lists" do
  it "rejects nested list cycles before executing recipes" do
    agent, root = ProfileMitamaeSpecFixture.build("recipes/steps.list\n", "recipes/steps.list\n")
    begin
      expect_raises(ArgumentError, "recipe list cycle") { agent.apply_profile("rescue") }
      agent.interaction.commands.should be_empty
    ensure
      ProfileMitamaeSpecFixture.remove(root)
    end
  end
end
