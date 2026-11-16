DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
DEB_CACHE_PROXY_URL = "http://127.0.0.1:3142"

def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
  started_at = Time.instant
  report_deb_cache_progress(progress, "Preparing shared Debian package cache")

  report_deb_cache_stage(1, "Checking the shared directory", progress) do
    command = <<-BASH
      set -eu
      if ! mountpoint -q /mnt/shared; then
        echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
        exit 20
      fi
      probe=$(mktemp /mnt/shared/.grml-agent-deb-cache.XXXXXX)
      rm -f "$probe"
      df -h /mnt/shared | tail -n 1
    BASH
    run_deb_cache_command(command)
  end

  report_deb_cache_stage(2, "Checking or installing apt-cacher-ng", progress) do
    command = <<-BASH
      set -eu
      if dpkg-query -W -f='${Status}\n' apt-cacher-ng 2>/dev/null | grep -qx 'install ok installed'; then
        echo "apt-cacher-ng is already installed"
      else
        echo "Installing apt-cacher-ng; this first installation requires network access"
        export DEBIAN_FRONTEND=noninteractive
        apt-get -o Acquire::http::Proxy=DIRECT update
        apt-get -o Acquire::http::Proxy=DIRECT install -y --no-install-recommends apt-cacher-ng
        echo "apt-cacher-ng installation completed"
      fi
    BASH
    run_deb_cache_command(command, 5.minutes, progress)
  end

  report_deb_cache_stage(3, "Preparing persistent cache storage", progress) do
    command = <<-BASH
      set -eu
      cache_path='#{DEB_CACHE_DIRECTORY}/proxy'
      service_dropin="/etc/systemd/system/apt-cacher-ng.service.d/grml-shared-cache.conf"

      mkdir -p "$cache_path"
      install -d -o apt-cacher-ng -g apt-cacher-ng -m 0755 "$cache_path"

      # Load after Debian's zz_debconf.conf so this CacheDir takes precedence.
      rm -f /etc/apt-cacher-ng/90-grml-agent.conf
      printf '%s\\n' \\
        'CacheDir: /mnt/shared/deb-cache/proxy' \\
        'BindAddress: 127.0.0.1' \\
        'ReportPage: acng-report.html' \\
        > /etc/apt-cacher-ng/zzzz-grml-agent.conf

      # Debian's service restricts writable paths. Permit the persistent
      # shared cache and prevent startup before the 9p mount exists.
      mkdir -p "$(dirname "$service_dropin")"
      printf '%s\\n' \\
        '[Unit]' \\
        'ConditionPathIsMountPoint=/mnt/shared' \\
        '' \\
        '[Service]' \\
        'ReadWritePaths=/mnt/shared/deb-cache/proxy' \\
        > "$service_dropin"

      if ! runuser -u apt-cacher-ng -- test -w "$cache_path"; then
        echo "apt-cacher-ng cannot write to shared cache directory: $cache_path" >&2
        exit 22
      fi

      printf 'Cache directory: %s\n' "$cache_path"
      echo "apt-cacher-ng service-user write access: OK"
    BASH
    run_deb_cache_command(command)
  end

  report_deb_cache_stage(4, "Configuring APT and grml-live", progress) do
    command = <<-BASH
      set -eu
      proxy_url='#{DEB_CACHE_PROXY_URL}'

      printf '%s\\n' 'Acquire::http::Proxy "http://127.0.0.1:3142";' \\
        > /etc/apt/apt.conf.d/90-grml-agent-deb-cache

      mkdir -p /etc/profile.d
      printf '%s\\n' 'export APT_PROXY="http://127.0.0.1:3142"' \\
        > /etc/profile.d/90-grml-agent-deb-cache.sh
      chmod 0644 /etc/apt/apt.conf.d/90-grml-agent-deb-cache /etc/profile.d/90-grml-agent-deb-cache.sh

      if [ -f /etc/environment ]; then
        sed -i '/^APT_PROXY=/d' /etc/environment
      fi
      printf 'APT_PROXY=%s\n' "$proxy_url" >> /etc/environment

      printf 'APT HTTP proxy: %s\nAPT_PROXY: %s\n' "$proxy_url" "$proxy_url"
    BASH
    run_deb_cache_command(command)
  end

  report_deb_cache_stage(5, "Starting apt-cacher-ng", progress) do
    command = <<-BASH
      set -eu
      # A forced VM shutdown during verify_deb_cache can leave its temporary
      # offline-mode override behind. Always restore normal upstream access
      # when preparing the cache after a boot.
      rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'
      systemctl daemon-reload

      diagnose_start_failure() {
        systemctl --no-pager --full status apt-cacher-ng.service >&2 || true
        journalctl -u apt-cacher-ng.service -b -n 80 --no-pager >&2 || true

        for log_file in /var/log/apt-cacher-ng/*.err; do
          if [ -f "$log_file" ]; then
            echo "----- $log_file -----" >&2
            tail -n 80 "$log_file" >&2 || true
          fi
        done
      }

      if ! systemctl restart apt-cacher-ng.service; then
        diagnose_start_failure
        echo "apt-cacher-ng could not be restarted" >&2
        exit 24
      fi

      if ! systemctl is-active --quiet apt-cacher-ng.service; then
        diagnose_start_failure
        echo "apt-cacher-ng did not remain active after restart" >&2
        exit 25
      fi

      systemctl is-active apt-cacher-ng.service
    BASH
    run_deb_cache_command(command, 45.seconds)
  end

  report_deb_cache_stage(6, "Checking proxy readiness", progress) do
    command = <<-BASH
      set -eu
      ready=0
      for attempt in $(seq 1 15); do
        if systemctl is-active --quiet apt-cacher-ng &&
           curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
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

      echo "Service: active"
      echo "Report endpoint: http://127.0.0.1:3142/acng-report.html (HTTP OK)"
    BASH
    run_deb_cache_command(command, 30.seconds)
  end

  report_deb_cache_stage(7, "Reporting cache status", progress) do
    command = <<-BASH
      set -eu
      cache_path='#{DEB_CACHE_DIRECTORY}/proxy'
      package_count=$(find "$cache_path" -type f -name '*.deb' | wc -l | tr -d '[:space:]')
      cache_size=$(du -sh "$cache_path" | cut -f1)
      free_bytes=$(df -PB1 /mnt/shared | awk 'NR == 2 {print $4}')
      proxy_setting=$(apt-config dump | awk -F '"' '/Acquire::http::Proxy / {print $2; exit}')
      environment_proxy=$(sed -n 's/^APT_PROXY=//p' /etc/environment | tail -n 1)

      printf 'Cache directory: %s\nCached .deb archives: %s\nCache size: %s\nShared filesystem free: %s bytes\nService: %s\nAPT HTTP proxy: %s\nAPT_PROXY in /etc/environment: %s\nPackage cache verification: not run (use verify_deb_cache [package])\n' \
        "$cache_path" "$package_count" "$cache_size" "$free_bytes" \
        "$(systemctl is-active apt-cacher-ng)" "$proxy_setting" "$environment_proxy"
    BASH
    run_deb_cache_command(command)
  end

  elapsed = Time.instant - started_at
  report_deb_cache_progress(progress, "Shared Debian package cache is ready")
  report_deb_cache_progress(progress, "Package reuse is not yet verified; run verify_deb_cache [package]")
  report_deb_cache_progress(progress, "Total preparation time: #{elapsed.total_seconds.round(1)}s")
end

private def report_deb_cache_stage(
  index : Int32,
  title : String,
  progress : Proc(String, Nil)?,
  &block : -> String
) : Nil
  label = "[#{index}/7] #{title}"
  started_at = Time.instant
  report_deb_cache_progress(progress, "#{label} ...")

  begin
    details = yield
  rescue ex
    elapsed = Time.instant - started_at
    report_deb_cache_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
    raise "Failed during #{title}: #{ex.message}"
  end

  elapsed = Time.instant - started_at
  report_deb_cache_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
  report_deb_cache_progress(progress, details) unless details.empty?
end

private def run_deb_cache_command(
  command : String,
  timeout : Time::Span = 30.seconds,
  progress : Proc(String, Nil)? = nil
) : String
  result = @interaction.execute_streaming(command, timeout) do |_stream, chunk|
    report_deb_cache_output(progress, chunk)
  end
  unless result.success?
    raise "Guest command failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end

  ""
end

private def report_deb_cache_output(progress : Proc(String, Nil)?, chunk : String) : Nil
  return if chunk.empty?

  if callback = progress
    callback.call(chunk)
  else
    Log.info { chunk }
  end
end

private def report_deb_cache_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call("#{message}\n")
  else
    Log.info { message }
  end
end
