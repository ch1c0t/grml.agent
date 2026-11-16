DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
DEB_CACHE_PROXY_URL = "http://127.0.0.1:3142"

def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
  report_deb_cache_progress(progress, "Preparing shared Debian package cache")

  command = <<-BASH
    set -eu

    cache_directory='#{DEB_CACHE_DIRECTORY}'
    proxy_url='#{DEB_CACHE_PROXY_URL}'

    if ! mountpoint -q /mnt/shared; then
      echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
      exit 20
    fi

    mkdir -p "$cache_directory/proxy"

    if ! dpkg-query -W -f='${Status}\n' apt-cacher-ng 2>/dev/null | grep -qx 'install ok installed'; then
      echo "apt-cacher-ng is not installed; installing it (this first installation requires network access)"
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y --no-install-recommends apt-cacher-ng
    fi

    install -d -o apt-cacher-ng -g apt-cacher-ng -m 0755 "$cache_directory/proxy"

    cat > /etc/apt-cacher-ng/90-grml-agent.conf <<'EOF'
    CacheDir: /mnt/shared/deb-cache/proxy
    BindAddress: 127.0.0.1
    EOF

    cat > /etc/apt/apt.conf.d/90-grml-agent-deb-cache <<'EOF'
    Acquire::http::Proxy "http://127.0.0.1:3142";
    EOF

    mkdir -p /etc/profile.d
    cat > /etc/profile.d/90-grml-agent-deb-cache.sh <<'EOF'
    export APT_PROXY="http://127.0.0.1:3142"
    EOF
    chmod 0644 /etc/apt/apt.conf.d/90-grml-agent-deb-cache /etc/profile.d/90-grml-agent-deb-cache.sh

    if [ -f /etc/environment ]; then
      sed -i '/^APT_PROXY=/d' /etc/environment
    fi
    printf 'APT_PROXY=%s\n' "$proxy_url" >> /etc/environment

    service apt-cacher-ng restart

    ready=0
    for attempt in $(seq 1 15); do
      if curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done

    if [ "$ready" -ne 1 ]; then
      echo "apt-cacher-ng did not become ready on 127.0.0.1:3142" >&2
      exit 21
    fi

    package_count=$(find "$cache_directory/proxy" -type f -name '*.deb' | wc -l | tr -d '[:space:]')
    cache_size=$(du -sh "$cache_directory/proxy" | cut -f1)
    printf 'Cache directory: %s/proxy\nCached .deb files: %s\nCache size: %s\nAPT proxy: %s\n' \
      "$cache_directory" "$package_count" "$cache_size" "$proxy_url"
  BASH

  result = @interaction.execute(command, 5.minutes)
  unless result.success?
    report_deb_cache_progress(progress, "Shared Debian package cache setup failed")
    raise "Could not prepare shared Debian package cache (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end

  report_deb_cache_progress(progress, result.stdout.strip)
  report_deb_cache_progress(
    progress,
    "The current shell may need: source /etc/profile.d/90-grml-agent-deb-cache.sh"
  )
end

private def report_deb_cache_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call(message)
  else
    Log.info { message }
  end
end
