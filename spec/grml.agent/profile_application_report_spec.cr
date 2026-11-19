require "spec"
require "file_utils"
require "../../src/logger"
require "../../src/grml"

describe GRML::ProfileApplicationReport do
  it "persists the initial report, operation results, and streamed output" do
    root = File.join(Dir.tempdir, "profile-report-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
    begin
      report = GRML::ProfileApplicationReport.new(root, "development", "spec")
      report.status.should eq("running")
      File.exists?(report.report_path).should be_true
      profile = report.add_profile("base", ["curl"], ["mitamae"], ["recipes/base.rb"])
      report.run_operation(profile.name, "packages", "curl") { |_operation| nil }
      report.append_output("package installation output\n")
      report.finish_profile(profile, "success")
      report.finish("success")
      json = JSON.parse(File.read(report.report_path))
      json["status"].as_s.should eq("success")
      json["origin"].as_s.should eq("spec")
      json["operations"][0]["status"].as_s.should eq("success")
      File.read(report.log_path).should contain("package installation output")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
