require "spec"
require "file_utils"
require "../../src/logger"
require "../../src/grml"
class GRMLAttachedDiskFakeVM
  getter commands = [] of String
  getter display : String? = ":88"; getter monitor_path = "/tmp/grml-attached-disk.sock"; getter iso_path : String? = nil
  def running? : Bool; true; end
  def initialize(@path : String); end
  def execute_qmp(command : String, arguments : Hash(String, JSON::Any)? = nil) : JSON::Any
    @commands << command
    JSON.parse({"return" => [{"node-name" => "grml_disk_build-test", "drv" => "qcow2", "file" => @path, "image" => {"format" => "qcow2", "virtual-size" => 1_073_741_824}}]}.to_json)
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
  it "uses the explicitly named QEMU block node while the disk is attached" do
    directory = "/tmp/grml-attached-#{Process.pid}"
    FileUtils.rm_rf(directory)
    FileUtils.mkdir_p(File.join(directory, "disks"))
    path = File.join(directory, "disks", "build-test.qcow2")
    File.write(path, "")
    vm = GRMLAttachedDiskFakeVM.new(path)
    begin
      result = Dir.cd(directory) { GRMLAttachedDiskHarness.new(vm).prepare("build-test", "1G") }
      result.should eq(path)
      vm.commands.should eq(["query-named-block-nodes"])
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
