require "spec"
require "../../src/logger"
require "../../src/grml"

class DiskImageSizeHarness
  include GRML::Agent::Storage
  def virtual_size(json : String) : Int64
    disk_image_virtual_size(json)
  end
end

describe "GRML disk image size" do
  it "reads a 32 GiB qcow2 virtual size without Int32 overflow" do
    size = DiskImageSizeHarness.new.virtual_size(%({"virtual-size":34359738368}))
    size.should eq(34_359_738_368_i64)
  end
end
