require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLGuestDiskLookupHarness
  include GRML::Agent::Storage
  def command : String
    ensure_ext4_provisioning_command("grml-live-build", "/mnt/grml-live-build")
  end
end

describe "GRML guest disk lookup" do
  it "can identify virtio disks by sysfs serial without udev by-id links" do
    command = GRMLGuestDiskLookupHarness.new.command
    command.should contain("/sys/block/vd*/serial")
    command.should contain("actual_serial")
    command.should contain("report_missing_ext4_disk")
    command.should contain("partition=\"$disk-part1\"")
    command.should contain("partition=\"${disk}1\"")
    command.should contain("NAME,PATH,TYPE,SIZE,SERIAL,FSTYPE,LABEL,MOUNTPOINTS")
  end
end
