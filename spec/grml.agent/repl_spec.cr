require "spec"
require "../../src/logger"
require "../../src/grml"

struct FakeGRMLOCRResult
  getter text : String
  getter error : String?
  getter timestamp : Int64

  def initialize(@text : String = "", @error : String? = nil, @timestamp : Int64 = 0_i64)
  end
end

struct FakeGRMLCommandResult
  getter exit_code : Int32
  getter stdout : String
  getter stderr : String

  def initialize(@exit_code : Int32 = 0, @stdout : String = "", @stderr : String = "")
  end

  def success? : Bool
    @exit_code == 0
  end
end

class FakeGRMLInteraction
  def latest_ocr : FakeGRMLOCRResult
    FakeGRMLOCRResult.new
  end

  def execute(command : String, timeout : Time::Span = 30.seconds) : FakeGRMLCommandResult
    FakeGRMLCommandResult.new(0, "guest output\n")
  end

  def execute_streaming(
    command : String,
    timeout : Time::Span = 30.seconds,
    &on_output : Symbol, String ->
  ) : FakeGRMLCommandResult
    result = execute(command, timeout)
    yield :stdout, result.stdout unless result.stdout.empty?
    yield :stderr, result.stderr unless result.stderr.empty?
    result
  end
end

class FakeGRMLAgent
  getter interaction : FakeGRMLInteraction
  getter prepared_branches = [] of String
  getter deb_cache_preparations = 0
  getter deb_cache_verifications = [] of String
  getter applied_profiles = [] of String
  getter shared_directory_verifications = 0
  getter prepared_build_profiles = [] of String
  getter validated_build_profiles = [] of String
  getter built_iso_profiles = [] of String
  getter created_disks = [] of Tuple(String, String, String)
  getter attached_disks = [] of Tuple(String, String)
  getter ext4_disks = [] of Tuple(String, String, String?, String)

  def initialize
    @interaction = FakeGRMLInteraction.new
  end

  def prepare_alpine_bundle(
    branch : String = "latest-stable",
    progress : Proc(String, Nil)? = nil
  ) : Nil
    @prepared_branches << branch
    progress.try &.call("fake preparation progress")
  end

  def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
    @deb_cache_preparations += 1
    progress.try &.call("fake Debian cache preparation progress")
  end

  def verify_shared_directory : Nil
    @shared_directory_verifications += 1
  end

  def apply_profile(profile_name : String, verify_cache : Bool = false, progress : Proc(String, Nil)? = nil) : Nil
    @applied_profiles << profile_name
    progress.try &.call("fake profile application progress")
  end

  def prepare_build_environment(profile_name : String, progress : Proc(String, Nil)? = nil) : Nil
    @prepared_build_profiles << profile_name
    progress.try &.call("fake build environment progress")
  end

  def validate_profile(profile_name : String, progress : Proc(String, Nil)? = nil) : GRML::LiveBuildManifest
    @validated_build_profiles << profile_name
    progress.try &.call("fake profile validation progress")
    GRML::LiveBuildManifest.from_json(%({"classes":["GRML_SMALL","RESCUE"]}))
  end

  def build_iso(profile_name : String, progress : Proc(String, Nil)? = nil) : String
    @built_iso_profiles << profile_name
    progress.try &.call("fake ISO build progress")
    "/mnt/shared/grml-live/runs/#{profile_name}/run/output"
  end

  def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil
    @deb_cache_verifications << package
    progress.try &.call("fake Debian cache verification progress")
  end

  def create_disk(name : String, size : String, format : String = "qcow2") : String
    @created_disks << {name, size, format}
    "./disks/#{name}.#{format}"
  end

  def attach_disk(path : String, format : String = "qcow2") : String
    @attached_disks << {path, format}
    "fake-device"
  end

  def create_ext4_disk(name : String, size : String, mountpoint : String? = nil, format : String = "qcow2") : String
    @ext4_disks << {name, size, mountpoint, format}
    "./disks/#{name}.#{format} (ext4 mounted)"
  end
end

def with_grml_repl_focus(value : String?, &block : -> T) : T forall T
  previous = ENV[GRML::REPL::FOCUS_ENV]?

  if value
    ENV[GRML::REPL::FOCUS_ENV] = value
  else
    ENV.delete(GRML::REPL::FOCUS_ENV)
  end

  yield
ensure
  if previous
    ENV[GRML::REPL::FOCUS_ENV] = previous
  else
    ENV.delete(GRML::REPL::FOCUS_ENV)
  end
end

describe GRML::REPL do
  it "focuses the REPL by default" do
    with_grml_repl_focus(nil) do
      GRML::REPL.focus?.should be_true
    end
  end

  it "accepts common true values" do
    {"true", "TRUE", "yes", "on", "1"}.each do |value|
      with_grml_repl_focus(value) do
        GRML::REPL.focus?.should be_true
      end
    end
  end

  it "accepts common false values" do
    {"false", "FALSE", "no", "off", "0"}.each do |value|
      with_grml_repl_focus(value) do
        GRML::REPL.focus?.should be_false
      end
    end
  end

  it "rejects invalid focus values" do
    with_grml_repl_focus("sometimes") do
      expect_raises(ArgumentError, "GRML_AGENT_REPL_FOCUS") do
        GRML::REPL.focus?
      end
    end
  end

  it "registers the commands contributed by each command module" do
    definition = GRML::REPL.build_definition(FakeGRMLAgent.new)
    definition.command_names.should eq([
      "apply_profile",
      "attach_disk",
      "build_iso",
      "copy_executable",
      "create_disk",
      "create_ext4_disk",
      "guest_exec",
      "ocr",
      "prepare_alpine_bundle",
      "prepare_build_environment",
      "prepare_deb_cache",
      "validate_profile",
      "verify_deb_cache",
    ])
  end


  it "prepares the shared Debian package cache without accepting arguments" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.prepare_deb_cache(agent, [] of String, progress)

    result.should contain("/mnt/shared/deb-cache")
    agent.deb_cache_preparations.should eq(1)
    messages.should eq(["fake Debian cache preparation progress"])

    expect_raises(ArgumentError, "Usage: prepare_deb_cache") do
      GRML::REPL.prepare_deb_cache(agent, ["unexpected"])
    end
    agent.deb_cache_preparations.should eq(1)
  end

  it "verifies the shared Debian cache using hello by default" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.verify_deb_cache(agent, [] of String, progress)

    result.should contain("hello")
    agent.deb_cache_verifications.should eq(["hello"])
    messages.should eq(["fake Debian cache verification progress"])
  end

  it "applies one named package profile and forwards progress" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.apply_profile(agent, ["development"], progress)

    result.should contain("development")
    result.should contain("additive")
    agent.shared_directory_verifications.should eq(1)
    agent.applied_profiles.should eq(["development"])
    messages.should eq(["fake profile application progress"])
  end

  it "rejects missing, multiple, or unsafe profile arguments" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Usage: apply_profile PROFILE_NAME") do
      GRML::REPL.apply_profile(agent, [] of String)
    end
    expect_raises(ArgumentError, "Usage: apply_profile PROFILE_NAME") do
      GRML::REPL.apply_profile(agent, ["development", "minimal"])
    end
    expect_raises(ArgumentError, "Invalid profile name") do
      GRML::REPL.apply_profile(agent, ["../development"])
    end

    agent.applied_profiles.should be_empty
  end

  it "prepares a profile build environment and forwards progress" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.prepare_build_environment(agent, ["rescue"], progress)

    result.should contain("rescue")
    agent.shared_directory_verifications.should eq(1)
    agent.prepared_build_profiles.should eq(["rescue"])
    messages.should eq(["fake build environment progress"])
  end

  it "validates a build profile and returns its suite and classes" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.validate_profile(agent, ["rescue"], progress)

    result.should contain("trixie")
    result.should contain("GRML_SMALL,RESCUE")
    agent.shared_directory_verifications.should eq(1)
    agent.validated_build_profiles.should eq(["rescue"])
    messages.should eq(["fake profile validation progress"])
  end

  it "builds an ISO and returns its shared artifact directory" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    result = GRML::REPL.build_iso(agent, ["rescue"], progress)

    result.should contain("/mnt/shared/grml-live/runs/rescue/")
    agent.shared_directory_verifications.should eq(1)
    agent.built_iso_profiles.should eq(["rescue"])
    messages.should eq(["fake ISO build progress"])
  end

  it "rejects invalid arguments for build profile commands" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Usage: prepare_build_environment PROFILE_NAME") do
      GRML::REPL.prepare_build_environment(agent, [] of String)
    end
    expect_raises(ArgumentError, "Usage: validate_profile PROFILE_NAME") do
      GRML::REPL.validate_profile(agent, ["rescue", "extra"])
    end
    expect_raises(ArgumentError, "Invalid profile name") do
      GRML::REPL.build_iso(agent, ["../rescue"])
    end

    agent.shared_directory_verifications.should eq(0)
    agent.prepared_build_profiles.should be_empty
    agent.validated_build_profiles.should be_empty
    agent.built_iso_profiles.should be_empty
  end

  it "accepts one safe package name for cache verification" do
    agent = FakeGRMLAgent.new

    result = GRML::REPL.verify_deb_cache(agent, ["bash"])

    result.should contain("bash")
    agent.deb_cache_verifications.should eq(["bash"])
  end

  it "rejects multiple or unsafe cache verification arguments" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Usage: verify_deb_cache [package]") do
      GRML::REPL.verify_deb_cache(agent, ["hello", "bash"])
    end

    expect_raises(ArgumentError, "Invalid Debian package name") do
      GRML::REPL.verify_deb_cache(agent, ["hello;touch"])
    end

    agent.deb_cache_verifications.should be_empty
  end

  it "defaults bundle preparation to latest-stable" do
    agent = FakeGRMLAgent.new

    result = GRML::REPL.prepare_alpine_bundle(agent, [] of String)

    result.should contain("latest-stable")
    agent.prepared_branches.should eq(["latest-stable"])
  end

  it "forwards progress messages to the supplied callback" do
    agent = FakeGRMLAgent.new
    messages = [] of String
    progress = ->(message : String) { messages << message; nil }

    GRML::REPL.prepare_alpine_bundle(agent, [] of String, progress)

    messages.should eq(["fake preparation progress"])
    agent.prepared_branches.should eq(["latest-stable"])
  end

  it "can prepare the bundle repeatedly using the same booted agent" do
    agent = FakeGRMLAgent.new

    GRML::REPL.prepare_alpine_bundle(agent, [] of String)
    GRML::REPL.prepare_alpine_bundle(agent, ["v3.24"])

    agent.prepared_branches.should eq(["latest-stable", "v3.24"])
  end

  it "rejects multiple branch arguments" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Usage: prepare_alpine_bundle") do
      GRML::REPL.prepare_alpine_bundle(agent, ["v3.24", "v3.25"])
    end

    agent.prepared_branches.should be_empty
  end

  it "rejects unsafe branch names" do
    agent = FakeGRMLAgent.new

    expect_raises(ArgumentError, "Invalid Alpine branch") do
      GRML::REPL.prepare_alpine_bundle(agent, ["v3.24; touch /tmp/pwned"])
    end

    agent.prepared_branches.should be_empty
  end
end
