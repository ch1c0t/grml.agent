require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBuildProfileValidationFakeInteraction
  getter commands = [] of String
  property manifest_json = %({"suite":"trixie","classes":["GRML_SMALL","RESCUE"],"grml_live_ref":"master"})
  property builder_packages = "git\n"
  property symlink_output = ""

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    @commands << command

    if command.includes?("if [ ! -d '/mnt/shared/profiles/rescue' ]")
      QEMU::CommandResult.new(0, "", "")
    elsif command.includes?("python3 -")
      QEMU::CommandResult.new(0, @manifest_json, "")
    elsif command.includes?("awk '")
      QEMU::CommandResult.new(0, @builder_packages, "")
    else
      QEMU::CommandResult.new(0, "", "")
    end
  end
end

class GRMLBuildProfileValidationHarness
  include GRML::Agent::ValidateBuildProfile

  def initialize(@interaction : GRMLBuildProfileValidationFakeInteraction)
  end
end

describe GRML::Agent::ValidateBuildProfile do
  it "validates a manifest, the builder package list, and custom class definitions" do
    interaction = GRMLBuildProfileValidationFakeInteraction.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }
    agent = GRMLBuildProfileValidationHarness.new(interaction)

    manifest = agent.validate_profile("rescue", progress)

    manifest.suite.should eq("trixie")
    manifest.classes_argument.should eq("GRML_SMALL,RESCUE")
    interaction.commands.size.should eq(4)
    interaction.commands[0].should contain("if [ ! -d '/mnt/shared/profiles/rescue' ]")
    interaction.commands[0].should contain("build.yml")
    interaction.commands[1].should contain("python3 -")
    interaction.commands[2].should contain("builder-packages.txt")
    interaction.commands[3].should contain("RESCUE")
    interaction.commands[3].should contain("bootstrap-keyring")
    messages.last.should contain("is valid")
  end

  it "does not reject symbolic links in filesystem overlays" do
    interaction = GRMLBuildProfileValidationFakeInteraction.new
    interaction.symlink_output = "/mnt/shared/profiles/rescue/grml-live/config/files/RESCUE/etc/passwd\n"
    agent = GRMLBuildProfileValidationHarness.new(interaction)

    manifest = agent.validate_profile("rescue")

    manifest.classes_argument.should eq("GRML_SMALL,RESCUE")
    interaction.commands[0].should_not contain("-type l")
  end

  it "rejects a manifest that requests a class selected automatically by grml-live" do
    interaction = GRMLBuildProfileValidationFakeInteraction.new
    interaction.manifest_json = %({"classes":["GRMLBASE"]})
    agent = GRMLBuildProfileValidationHarness.new(interaction)

    expect_raises(ArgumentError, "added automatically") do
      agent.validate_profile("rescue")
    end

    interaction.commands.size.should eq(2)
  end

  it "rejects unsafe profile names before executing guest commands" do
    interaction = GRMLBuildProfileValidationFakeInteraction.new
    agent = GRMLBuildProfileValidationHarness.new(interaction)

    expect_raises(ArgumentError, "Invalid profile name") do
      agent.validate_profile("../rescue")
    end

    interaction.commands.should be_empty
  end
end
