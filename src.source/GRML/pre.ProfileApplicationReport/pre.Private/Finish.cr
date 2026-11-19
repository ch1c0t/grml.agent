def finish_profile(profile : ProfileApplicationProfile, status : String) : Nil
  profile.status = status
  persist
end

def finish(status : String, error : String? = nil) : Nil
  @status, @error = status, error
  @profiles.each { |p| p.status = "not_started" if p.status == "pending" && status == "failed" }
  @finished_at = profile_report_timestamp
  persist
end
