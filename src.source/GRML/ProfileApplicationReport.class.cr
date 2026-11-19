include Private
include JSON::Serializable

property schema_version : Int32 = 1
property run_id : String
property origin : String
property requested_profile : String
property status : String = "running"
property started_at : String
property finished_at : String? = nil
property error : String? = nil
property output_log : String = "output.log"
property profiles = [] of ProfileApplicationProfile
property operations = [] of ProfileApplicationOperation
@[JSON::Field(ignore: true)] property report_path : String
@[JSON::Field(ignore: true)] property log_path : String

def initialize(shared_path : String, @requested_profile : String, @origin : String)
  @started_at = profile_report_timestamp
  stamp = @started_at.gsub(/[-:TZ]/, "")
  @run_id = "#{stamp}-#{Process.pid}-#{Random.rand(1..1_000_000)}"
  directory = File.join(shared_path, "profile-applications", @run_id)
  Dir.mkdir_p(directory)
  @report_path = File.join(directory, "report.json")
  @log_path = File.join(directory, output_log)
  File.write(@log_path, "")
  persist
end
