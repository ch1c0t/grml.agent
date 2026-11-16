DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
DEB_CACHE_PROXY_URL = "http://127.0.0.1:3142"

def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
  report_deb_cache_progress(progress, "Preparing shared Debian package cache")

  command = <<-BASH
    set -eu

    cache_directory='#{DEB_CACHE_DIRECTORY}'
    proxy_url='#{DEB_CACHE_PROXY_URL}'
    cache_path="$cache_directory/proxy"
    service_dropin="/etc/systemd/system/apt-cacher-ng.service.d/grml-shared-cache.conf"

    if ! mountpoint -q /mnt/shared; then
      echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
      exit 20
    fi

    mkdir -p "$cache_path"

    if ! dpkg-query -W -f='${Status}\n' apt-cacher-ng 2>/dev/null | grep -qx 'install ok installed'; then
      echo "apt-cacher-ng is not installed; installing it (this first installation requires network access)"
      export DEBIAN_FRONTEND=noninteractive
      apt-get -o Acquire::http::Proxy=DIRECT update
      apt-get -o Acquire::http::Proxy=DIRECT install -y --no-install-recommends apt-cacher-ng
    fi

    install -d -o apt-cacher-ng -g apt-cacher-ng -m 0755 "$cache_path"

    # Load after Debian's zz_debconf.conf so this CacheDir takes precedence.
    rm -f /etc/apt-cacher-ng/90-grml-agent.conf
    cat > /etc/apt-cacher-ng/zzzz-grml-agent.conf <<'EOF'
    CacheDir: /mnt/shared/deb-cache/proxy
    BindAddress: 127.0.0.1
    EOF

    # The Debian service restricts its writable paths. Allow the shared cache
    # and wait until the 9p mount exists before starting the daemon.
    mkdir -p "$(dirname "$service_dropin")"
    cat > "$service_dropin" <<'EOF'
    [Unit]
    ConditionPathIsMountPoint=/mnt/shared

    [Service]
    WorkingDirectory=/mnt/shared/deb-cache/proxy
    ReadWritePaths=/mnt/shared/deb-cache/proxy
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

    systemctl daemon-reload
    systemctl restart apt-cacher-ng

    ready=0
    for attempt in $(seq 1 15); do
      if curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done

    if [ "$ready" -ne 1 ]; then
      systemctl --no-pager --full status apt-cacher-ng >&2 || true
      journalctl -u apt-cacher-ng -n 40 --no-pager >&2 || true
      echo "apt-cacher-ng did not become ready on 127.0.0.1:3142" >&2
      exit 21
    fi

    package_count=$(find "$cache_path" -type f -name '*.deb' | wc -l | tr -d '[:space:]')
    cache_size=$(du -sh "$cache_path" | cut -f1)
    printf 'Cache directory: %s\nCached .deb files: %s\nCache size: %s\nAPT proxy: %s\n' \
      "$cache_path" "$package_count" "$cache_size" "$proxy_url"
  BASH

  result = @interaction.execute(command, 5.minutes)
  unless result.success?
    report_deb_cache_progress(progress, "Shared Debian package cache setup failed")
    raise "Could not prepare shared Debian package cache (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end

  report_deb_cache_progress(progress, result.stdout.strip)
  report_deb_cache_progress(
    progress,
    "New login shells export APT_PROXY; source /etc/profile.d/90-grml-agent-deb-cache.sh in an existing shell"
  )
end

private def report_deb_cache_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call(message)
  else
    Log.info { message }
  end
end
