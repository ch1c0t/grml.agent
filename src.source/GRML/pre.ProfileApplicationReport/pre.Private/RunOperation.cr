def run_operation(profile : String?, kind : String, target : String,
                   &block : ProfileApplicationOperation -> Nil) : Nil
  operation = ProfileApplicationOperation.new(profile, kind, target)
  @operations << operation
  persist
  begin
    yield operation
    operation.finish("success")
  rescue exception
    operation.finish("failed", exception.to_s)
    raise
  ensure
    persist
  end
end

def skip_operation(profile : String?, kind : String, target : String) : Nil
  operation = ProfileApplicationOperation.new(profile, kind, target)
  operation.finish("skipped")
  @operations << operation
  persist
end
