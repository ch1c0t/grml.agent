def persist : Nil
  temporary = "#{@report_path}.tmp"
  File.write(temporary, to_pretty_json)
  File.rename(temporary, @report_path)
end

private def profile_report_timestamp : String
  Time.utc.to_s("%FT%TZ")
end
