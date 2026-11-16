DEFAULT_DEB_CACHE_VERIFICATION_PACKAGE = "hello"

def verify_deb_cache(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  if arguments.size > 1
    raise ArgumentError.new("Usage: verify_deb_cache [package]")
  end

  package = arguments.first? || DEFAULT_DEB_CACHE_VERIFICATION_PACKAGE
  unless package.matches?(/\A[a-z0-9][a-z0-9+.-]*\z/)
    raise ArgumentError.new("Invalid Debian package name: #{package.inspect}")
  end

  agent.verify_deb_cache(package, progress)
  "Verified shared Debian package cache using #{package}."
end
