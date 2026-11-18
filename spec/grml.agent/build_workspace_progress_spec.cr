require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLBuildWorkspaceProgressHarness
  include GRML::Agent::Storage
  def provisioning_command : String
    ensure_ext4_provisioning_command("grml-live-build", "/mnt/grml-live-build")
  end
end

describe "GRML build workspace progress" do
  it "announces disk wait, partitioning, formatting, mounting, and verification" do
    command = GRMLBuildWorkspaceProgressHarness.new.provisioning_command
    ["Waiting for guest disk", "Creating GPT", "Formatting", "Mounting", "Verifying"].each do |step|
      command.should contain(step)
    end
  end
end
