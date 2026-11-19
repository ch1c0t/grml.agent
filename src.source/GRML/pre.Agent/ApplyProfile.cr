DEBIAN_PROFILE_DIRECTORY = "/mnt/shared/profiles"
DEBIAN_PROFILE_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

def apply_profile(profile_name : String, verify_cache : Bool = false,
                  progress : Proc(String, Nil)? = nil) : Nil
  unless profile_name.matches?(DEBIAN_PROFILE_NAME_PATTERN)
    raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
  end
  executables = profile_host_executables(profile_name)
  packages = read_profile_packages(profile_name, progress)
  apply_profile_packages(profile_name, packages, verify_cache, progress)
  install_profile_host_executables(executables, progress)
end
