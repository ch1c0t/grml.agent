require "spec"
require "file_utils"
require "../../src/logger"
require "../../src/grml"

describe "profile application report failures" do
  it "preserves the failed operation and error" do
    root = File.join(Dir.tempdir, "profile-report-failed-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
    begin
      report = GRML::ProfileApplicationReport.new(root, "broken", "spec")
      expect_raises(Exception) do
        report.run_operation("broken", "mitamae_recipe", "recipes/fail.rb") { raise "recipe failed" }
      end
      report.finish("failed", "recipe failed")
      json = JSON.parse(File.read(report.report_path))
      json["status"].as_s.should eq("failed")
      json["operations"][0]["status"].as_s.should eq("failed")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
