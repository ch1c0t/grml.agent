require "spec"
require "../../src/logger"
require "../../src/grml"
require "../support/profile_mitamae_harness"
require "../support/profile_mitamae_fixture"

describe "profile Mitamae recipes" do
  it "executes listed recipes in order, resolving directories and nested lists" do
    agent, root = ProfileMitamaeSpecFixture.build("recipes/base.rb\nrecipes/steps.list\nrecipes/defaults\n")
    begin
      agent.apply_profile("rescue")
      commands = agent.interaction.commands
      commands.size.should eq(3)
      commands[0].should contain("/mnt/shared/profiles/rescue/recipes/base.rb")
      commands[1].should contain("/mnt/shared/profiles/rescue/recipes/second.rb")
      commands[2].should contain("/mnt/shared/profiles/rescue/recipes/defaults/default.rb")
      commands.all?(&.includes?("mitamae-node.yml")).should be_true
    ensure
      ProfileMitamaeSpecFixture.remove(root)
    end
  end

  it "rejects paths outside the profile before applying it" do
    agent, root = ProfileMitamaeSpecFixture.build("../outside.rb\n")
    begin
      expect_raises(ArgumentError, "stay inside profile") { agent.apply_profile("rescue") }
      agent.interaction.commands.should be_empty
    ensure
      ProfileMitamaeSpecFixture.remove(root)
    end
  end
end
