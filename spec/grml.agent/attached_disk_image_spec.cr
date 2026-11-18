require "spec"
require "file_utils"
require "../../src/logger"
require "../../src/grml"
class GRMLAttachedDiskFakeVM
  getter commands = [] of String
  def initialize(@path : String); end
  def execute_qmp(command : String, arguments : Hash(String, JSON::Any)? = nil) : JSON::Any
    @commands << command
    JSON.parse({"return" => [{"device" => "virtio-disk0", "qdev" => "grml_virtio_disk_build-test", "inserted" => {"file" => @path, "drv" => "qcow2", "image" => {"format" => "qcow2", "virtual-size" => 1_073_741_824}}}]}.to_json)
  end
end
class GRMLAttachedDiskHarness
  include GRML::Agent::Storage
  def initialize(@vm : GRMLAttachedDiskFakeVM); end
  def prepare(name : String, size : String) : String
    prepare_ext4_disk_image(name, size, "qcow2", nil)
  end
end
describe "GRML attached disk image" do
  it "matches the QEMU qdev ID instead of the block device name" do
    directory = "/tmp/grml-attached-#{Process.pid}"
    FileUtils.rm_rf(directory)
    FileUtils.mkdir_p(File.join(directory, "disks"))
    path = File.join(directory, "disks", "build-test.qcow2")
    File.write(path, "")
    vm = GRMLAttachedDiskFakeVM.new(path)
    begin
      result = Dir.cd(directory) { GRMLAttachedDiskHarness.new(vm).prepare("build-test", "1G") }
      result.should eq(path)
      vm.commands.should eq(["query-block"])
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
