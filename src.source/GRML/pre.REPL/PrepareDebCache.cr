DEFAULT_DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
DEFAULT_DEB_CACHE_PROXY_URL = "http://127.0.0.1:3142"

def prepare_deb_cache(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  raise ArgumentError.new("Usage: prepare_deb_cache") unless arguments.empty?

  agent.prepare_deb_cache(progress)
  "Prepared shared Debian package cache at #{DEFAULT_DEB_CACHE_DIRECTORY}."
end
