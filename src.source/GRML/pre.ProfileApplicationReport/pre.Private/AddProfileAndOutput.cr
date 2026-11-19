def add_profile(name : String, packages : Array(String),
                executables : Array(String), recipes : Array(String)) : ProfileApplicationProfile
  profile = ProfileApplicationProfile.new(name)
  profile.packages = packages
  profile.host_executables = executables
  profile.recipes = recipes
  @profiles << profile
  persist
  profile
end

def append_output(chunk : String) : Nil
  return if chunk.empty?
  File.open(@log_path, "a") { |file| file << chunk; file.flush }
end
