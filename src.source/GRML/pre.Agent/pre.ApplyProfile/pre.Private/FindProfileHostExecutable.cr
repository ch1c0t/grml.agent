private def find_profile_host_executable(name : String) : String?
  Process.find_executable(name)
end
