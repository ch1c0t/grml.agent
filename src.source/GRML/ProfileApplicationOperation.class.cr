include JSON::Serializable

property profile : String?
property kind : String
property target : String
property status : String = "running"
property started_at : String
property finished_at : String? = nil
property exit_code : Int32? = nil
property error : String? = nil

def initialize(@profile : String?, @kind : String, @target : String)
  @started_at = Time.utc.to_s("%FT%TZ")
end

def finish(status : String, error : String? = nil) : Nil
  @status, @error = status, error
  @finished_at = Time.utc.to_s("%FT%TZ")
end
