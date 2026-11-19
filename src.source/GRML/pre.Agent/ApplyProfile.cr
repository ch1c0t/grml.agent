include Private

DEBIAN_PROFILE_DIRECTORY = "/mnt/shared/profiles"
DEBIAN_PROFILE_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

def apply_profile(profile_name : String, verify_cache : Bool = false,
                  progress : Proc(String, Nil)? = nil) : Nil
  profiles = profile_application_order(profile_name).map do |name|
    {name, read_profile_packages(name, progress), profile_host_executables(name)}
  end
  profiles.each do |name, packages, executables|
    apply_profile_packages(name, packages, progress)
    install_profile_host_executables(executables, progress)
  end
  has_packages = profiles.any? { |profile| !profile[1].empty? }
  verify_profile_cache(profile_name, has_packages, verify_cache, progress)
end
