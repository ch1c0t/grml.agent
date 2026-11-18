require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBuildWorkspaceFakeVM
  property response : JSON::Any
  getter commands = [] of String

  def initialize(@response : JSON::Any = JSON.parse(%({"return":[]})))
  end

  def execute_qmp(command : String, arguments : Hash(String, JSON::Any)? = nil) : JSON::Any
    @commands << command
    @response
  end
end

class GRMLBuildWorkspaceFakeInteraction
  getter commands = [] of String

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    @commands << command
    QEMU::CommandResult.new(0, "", "")
  end
end

class GRMLBuildWorkspaceHarness
  include GRML::Agent::Storage

  def initialize(@vm : GRMLBuildWorkspaceFakeVM, @interaction : GRMLBuildWorkspaceFakeInteraction)
  end

  def attached_disk_path(device_id : String) : String?
    find_attached_disk_path(device_id)
  end

  def provisioning_command(serial : String, mountpoint : String) : String
    ensure_ext4_provisioning_command(serial, mountpoint)
  end

  def validated_mountpoint(mountpoint : String) : String
    validate_guest_mountpoint(mountpoint)
  end
end

describe GRML::Agent::Storage do
  it "finds a QEMU block device by its device ID and returns its backing file" do
    vm = GRMLBuildWorkspaceFakeVM.new(JSON.parse(%({
      "return": [
        {
          "device": "grml_virtio_disk_live_build",
          "inserted": {"file": "/work/disks/grml-live-build.qcow2"}
        }
      ]
    })))
    agent = GRMLBuildWorkspaceHarness.new(vm, GRMLBuildWorkspaceFakeInteraction.new)

    agent.attached_disk_path("grml_virtio_disk_live_build").should eq("/work/disks/grml-live-build.qcow2")
    vm.commands.should eq(["query-block"])
  end

  it "returns nil when the dedicated build disk is not attached" do
    vm = GRMLBuildWorkspaceFakeVM.new
    agent = GRMLBuildWorkspaceHarness.new(vm, GRMLBuildWorkspaceFakeInteraction.new)

    agent.attached_disk_path("grml_virtio_disk_live_build").should be_nil
  end

  it "reuses a matching ext4 mount and refuses to format unexpected filesystems" do
    agent = GRMLBuildWorkspaceHarness.new(GRMLBuildWorkspaceFakeVM.new, GRMLBuildWorkspaceFakeInteraction.new)
    command = agent.provisioning_command("grml-live-build", "/mnt/grml-live-build")

    command.should contain("mountpoint -q")
    command.should contain("mounted_type")
    command.should contain("readlink -f")
    command.should contain("filesystem")
    command.should contain("elif [ \"$filesystem\" != ext4 ]")
    command.should contain("refusing to format it")
    command.should contain("mkfs.ext4 -F \"$partition\"")
    command.should contain("blkid -p -o value -s PTTYPE")
    command.should_not contain("mkfs.ext4 -F \"$disk\"")
  end

  it "validates the guest mountpoint without permitting a root or traversal path" do
    agent = GRMLBuildWorkspaceHarness.new(GRMLBuildWorkspaceFakeVM.new, GRMLBuildWorkspaceFakeInteraction.new)

    expect_raises(ArgumentError, "Mount point must be an absolute guest path") do
      agent.validated_mountpoint("/")
    end
    expect_raises(ArgumentError, "Mount point must be an absolute guest path") do
      agent.validated_mountpoint("/mnt/../root")
    end
  end
end
