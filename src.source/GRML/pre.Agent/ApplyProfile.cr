include Private

DEBIAN_PROFILE_DIRECTORY = "/mnt/shared/profiles"
DEBIAN_PROFILE_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

def apply_profile(profile_name : String, verify_cache : Bool = false,
                  progress : Proc(String, Nil)? = nil, origin : String = "api") : Nil
  report = ProfileApplicationReport.new(@vm.shared_path, profile_name, origin)
  apply_profile_with_report(profile_name, verify_cache, progress, report)
end
