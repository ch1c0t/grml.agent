require "spec"
require "../../src/logger"
require "../../src/grml"
class GRMLStorageDiagnosticsVM
  getter commands = [] of String
  getter display : String? = ":88"
  getter monitor_path = "/tmp/grml-qmp-diagnostics.sock"
  getter iso_path : String? = nil
  def running? : Bool; true; end
  def execute_qmp(command : String, arguments : Hash(String, JSON::Any)? = nil) : JSON::Any
    @commands << command
    JSON.parse({"return" => [] of JSON::Any}.to_json)
  end
end
class GRMLStorageDiagnosticsHarness
  include GRML::Agent::Storage
  def initialize(@vm : GRMLStorageDiagnosticsVM); end
  def payload(path : String, node : String) : JSON::Any
    JSON.parse(storage_diagnostics_payload(path, node))
  end
end
describe "GRML storage diagnostics" do
  it "captures QMP responses, VM identity, and host lock inspection" do
    vm = GRMLStorageDiagnosticsVM.new
    payload = GRMLStorageDiagnosticsHarness.new(vm).payload("/tmp/build.qcow2", "grml_disk_live_build")
    payload["expected_node_name"].as_s.should eq("grml_disk_live_build")
    payload["vm"]["monitor_path"].as_s.should eq(vm.monitor_path)
    payload["qmp"].as_h.keys.should contain("query-named-block-nodes")
    payload["host"].as_h.keys.should contain("fuser_verbose")
    vm.commands.should eq(["query-named-block-nodes", "query-block", "query-status", "query-version"])
  end
end
