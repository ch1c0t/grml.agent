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
    JSON.parse({"return" => [{"device" => "virtio0", "qdev" => "/machine/peripheral-anon/device[3]/virtio-backend", "inserted" => {"node-name" => "#block167", "drv" => "qcow2", "file" => @path, "image" => {"filename" => @path, "format" => "qcow2", "virtual-size" => 1_073_741_824}}}]}.to_json)
  end
end
class GRMLAttachedDiskHarness
  include GRML::Agent::Storage
  def initialize(@vm : GRMLAttachedDiskFakeVM); end
  def prepare(name : String, size : String) : String
    path = prepare_ext4_disk_image(name, size, "qcow2", nil)
    ensure_ext4_disk_attachment(path, name, "qcow2", nil)
    path
  end
end
describe "GRML attached disk image" do
  it "reuses an auto-attached disk by backing path, not its generated node name" do
    directory = "/tmp/grml-attached-#{Process.pid}"
    FileUtils.rm_rf(directory); FileUtils.mkdir_p(File.join(directory, "disks"))
    path = File.join(directory, "disks", "build-test.qcow2"); File.write(path, "")
    vm = GRMLAttachedDiskFakeVM.new(path)
    begin
      result = Dir.cd(directory) { GRMLAttachedDiskHarness.new(vm).prepare("build-test", "1G") }
      result.should eq(path)
      vm.commands.should eq(["query-block", "query-block"])
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end