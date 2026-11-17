require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBootProfileFakeVM
  def send_key(key : String) : Nil
  end
end

class GRMLBootProfileFakeInteraction
  getter events : Array(String)
  getter streamed_commands = [] of String
  property profile_output = "git\nvim\n"
  property profile_exit_code = 0
  property profile_stderr = ""

  def initialize(@events : Array(String))
  end

  def wait_for_text(
    text : String,
    timeout : Time::Span = 30.seconds,
    region : Symbol? = nil
  ) : Nil
  end

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    if command.includes?("qemu-guest-agent-ok")
      QEMU::CommandResult.new(0, "qemu-guest-agent-ok\n", "")
    elsif command.includes?("awk '")
      @events << "read-profile"
      QEMU::CommandResult.new(@profile_exit_code, @profile_output, @profile_stderr)
    else
      QEMU::CommandResult.new(0, "", "")
    end
  end

  def execute_streaming(
    command : String,
    timeout : Time::Span = 30.seconds,
    &on_output : Symbol, String ->
  ) : QEMU::CommandResult
    @streamed_commands << command
    @events << "install" if command.includes?("apt-get install")
    QEMU::CommandResult.new(0, "", "")
  end
end

class GRMLBootProfileHarness
  include GRML::Agent::Boot

  getter events : Array(String)

  def initialize(@interaction : GRMLBootProfileFakeInteraction, @events : Array(String))
    @vm = GRMLBootProfileFakeVM.new
  end

  def verify_shared_directory : Nil
    @events << "shared"
  end

  def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
    @events << "prepare-cache"
  end

  def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil
    @events << "verify-cache:#{package}"
  end
end

describe GRML::Agent::Boot do
  it "prepares the shared cache before refreshing metadata and installing profile packages" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    agent = GRMLBootProfileHarness.new(interaction, events)

    agent.boot("development")

    events.should eq(["shared", "read-profile", "prepare-cache", "install"])
    interaction.streamed_commands.size.should eq(1)
    interaction.streamed_commands[0].should contain("apt-get update")
    interaction.streamed_commands[0].should contain("DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git vim")
  end

  it "runs offline cache verification only when explicitly requested and after package installation" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    agent = GRMLBootProfileHarness.new(interaction, events)

    agent.boot("development", true)

    events.should eq(["shared", "read-profile", "prepare-cache", "install", "verify-cache:hello"])
  end

  it "does not prepare the cache for an empty package profile" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    interaction.profile_output = ""
    agent = GRMLBootProfileHarness.new(interaction, events)

    agent.boot("empty")

    events.should eq(["shared", "read-profile"])
    interaction.streamed_commands.should be_empty
  end

  it "leaves profile-less boots unchanged" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    agent = GRMLBootProfileHarness.new(interaction, events)

    agent.boot

    events.should eq(["shared"])
    interaction.streamed_commands.should be_empty
  end

  it "requires a profile when cache verification is requested" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    agent = GRMLBootProfileHarness.new(interaction, events)

    expect_raises(ArgumentError, "--verify-deb-cache requires a boot profile") do
      agent.boot(nil, true)
    end

    events.should be_empty
  end

  it "does not prepare the cache when the profile file is missing or invalid" do
    events = [] of String
    interaction = GRMLBootProfileFakeInteraction.new(events)
    interaction.profile_exit_code = 2
    interaction.profile_stderr = "Invalid Debian package name"
    agent = GRMLBootProfileHarness.new(interaction, events)

    expect_raises(Exception, "Could not read boot profile") do
      agent.boot("development")
    end

    events.should eq(["shared", "read-profile"])
  end
end
