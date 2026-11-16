DEB_CACHE_VERIFY_OFFLINE_CONFIG = "/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf"

def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil
  unless package.matches?(/\A[a-z0-9][a-z0-9+.-]*\z/)
    raise ArgumentError.new("Invalid Debian package name: #{package.inspect}")
  end

  started_at = Time.instant
  run_id = Random.rand(0_i64..Int64::MAX).to_s
  work_directory = "/tmp/grml-agent-deb-cache-verify-#{run_id}"
  offline_config = DEB_CACHE_VERIFY_OFFLINE_CONFIG
  offline_mode_may_be_enabled = false

  report_deb_cache_verification_progress(progress, "Verifying shared Debian package cache")
  report_deb_cache_verification_progress(progress, "Package: #{package}")

  begin
    report_deb_cache_verification_stage(1, "Checking proxy and APT configuration", progress) do
      command = <<-BASH
        set -eu
        if ! mountpoint -q /mnt/shared; then
          echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
          exit 20
        fi

        if ! runuser -u apt-cacher-ng -- test -w /mnt/shared/deb-cache/proxy; then
          echo "apt-cacher-ng cannot write to /mnt/shared/deb-cache/proxy" >&2
          exit 22
        fi

        # Recover from an interrupted verification before starting a new one.
        rm -f '#{offline_config}'
        systemctl restart apt-cacher-ng

        if ! apt-config dump | grep -Fqx 'Acquire::http::Proxy "http://127.0.0.1:3142";'; then
          echo "APT is not configured to use the shared-cache proxy" >&2
          exit 23
        fi

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
          echo "apt-cacher-ng is not ready" >&2
          exit 21
        fi

        echo "APT HTTP proxy and apt-cacher-ng are ready"
      BASH
      run_deb_cache_verification_command(command)
    end

    report_deb_cache_verification_stage(2, "Downloading the current package version", progress) do
      command = <<-BASH
        set -eu
        work_directory='#{work_directory}'
        package='#{package}'
        mkdir -m 0700 -p "$work_directory/online" "$work_directory/offline"

        apt-get update
        version=$(apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')
        if [ -z "$version" ] || [ "$version" = "(none)" ]; then
          echo "No candidate version is available for package: $package" >&2
          exit 40
        fi

        download_log="$work_directory/online/download.log"
        if ! (cd "$work_directory/online" && apt-get download "$package=$version") >"$download_log" 2>&1; then
          cat "$download_log" >&2
          exit 41
        fi
        cat "$download_log"

        if ! grep -Eq 'Get:[[:space:]]*[0-9]+[[:space:]]+http://' "$download_log"; then
          echo "The package was not fetched from an HTTP repository; this HTTP cache cannot verify HTTPS package payloads" >&2
          exit 42
        fi

        archive=$(find "$work_directory/online" -maxdepth 1 -type f -name '*.deb' -print -quit)
        if [ -z "$archive" ]; then
          echo "APT completed without producing a .deb archive" >&2
          exit 43
        fi

        checksum=$(sha256sum "$archive" | awk '{print $1}')
        bytes=$(stat -c '%s' "$archive")
        printf '%s\n%s\n' "$version" "$checksum" > "$work_directory/metadata"
        printf 'Package: %s\nVersion: %s\nFirst download SHA-256: %s\nArchive size: %s bytes\n' \
          "$package" "$version" "$checksum" "$bytes"
      BASH
      run_deb_cache_verification_command(command, 10.minutes)
    end

    offline_mode_may_be_enabled = true
    report_deb_cache_verification_stage(3, "Disabling upstream access", progress) do
      command = <<-BASH
        set -eu
        cat > '#{offline_config}' <<'EOF'
        Offlinemode: 1
        EOF

        systemctl restart apt-cacher-ng
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
          echo "apt-cacher-ng did not restart in offline mode" >&2
          exit 44
        fi

        echo "apt-cacher-ng is active with Offlinemode: 1"
      BASH
      run_deb_cache_verification_command(command, 30.seconds)
    end

    report_deb_cache_verification_stage(4, "Fetching the same version with upstream disabled", progress) do
      command = <<-BASH
        set -eu
        work_directory='#{work_directory}'
        package='#{package}'
        version=$(sed -n '1p' "$work_directory/metadata")
        expected_checksum=$(sed -n '2p' "$work_directory/metadata")
        download_log="$work_directory/offline/download.log"

        if [ -z "$version" ] || [ -z "$expected_checksum" ]; then
          echo "Missing metadata from the first package download" >&2
          exit 45
        fi

        if ! (cd "$work_directory/offline" && apt-get download "$package=$version") >"$download_log" 2>&1; then
          cat "$download_log" >&2
          echo "The package was not available from the cache while upstream access was disabled" >&2
          exit 46
        fi
        cat "$download_log"

        if ! grep -Eq 'Get:[[:space:]]*[0-9]+[[:space:]]+http://' "$download_log"; then
          echo "The offline package request did not use an HTTP repository URL" >&2
          exit 47
        fi

        archive=$(find "$work_directory/offline" -maxdepth 1 -type f -name '*.deb' -print -quit)
        if [ -z "$archive" ]; then
          echo "Offline APT download completed without producing a .deb archive" >&2
          exit 48
        fi

        actual_checksum=$(sha256sum "$archive" | awk '{print $1}')
        if [ "$actual_checksum" != "$expected_checksum" ]; then
          echo "Cached package checksum does not match the first download" >&2
          echo "Expected: $expected_checksum" >&2
          echo "Actual:   $actual_checksum" >&2
          exit 49
        fi

        printf 'Offline download SHA-256: %s\nCache verification: PASS (upstream disabled)\n' \
          "$actual_checksum"
      BASH
      run_deb_cache_verification_command(command, 5.minutes)
    end

    report_deb_cache_verification_stage(5, "Restoring normal proxy mode", progress) do
      result = run_deb_cache_verification_command(restore_deb_cache_proxy_command(offline_config), 30.seconds)
      offline_mode_may_be_enabled = false
      result
    end

    elapsed = Time.instant - started_at
    report_deb_cache_verification_progress(progress, "Shared Debian package cache verified for #{package}")
    report_deb_cache_verification_progress(progress, "The same package version was downloaded successfully with upstream access disabled")
    report_deb_cache_verification_progress(progress, "Total verification time: #{elapsed.total_seconds.round(1)}s")
  rescue ex
    report_deb_cache_verification_progress(progress, "Package cache verification FAILED: #{ex.message}")
    raise ex
  ensure
    if offline_mode_may_be_enabled
      begin
        cleanup_result = @interaction.execute(restore_deb_cache_proxy_command(offline_config), 30.seconds)
        if cleanup_result.success?
          report_deb_cache_verification_progress(progress, "Restored normal apt-cacher-ng mode after verification failure")
        else
          report_deb_cache_verification_progress(
            progress,
            "WARNING: could not restore apt-cacher-ng online mode: #{cleanup_result.stderr}\n#{cleanup_result.stdout}"
          )
        end
      rescue cleanup_error
        report_deb_cache_verification_progress(
          progress,
          "WARNING: could not restore apt-cacher-ng online mode: #{cleanup_error.message}"
        )
      end
    end

    begin
      cleanup_result = @interaction.execute("rm -rf '#{work_directory}'", 30.seconds)
      unless cleanup_result.success?
        report_deb_cache_verification_progress(progress, "WARNING: could not remove verification directory #{work_directory}")
      end
    rescue cleanup_error
      report_deb_cache_verification_progress(
        progress,
        "WARNING: could not remove verification directory #{work_directory}: #{cleanup_error.message}"
      )
    end
  end
end

private def restore_deb_cache_proxy_command(offline_config : String) : String
  <<-BASH
    set -eu
    rm -f '#{offline_config}'
    systemctl restart apt-cacher-ng

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
      echo "apt-cacher-ng did not return to online mode" >&2
      exit 50
    fi

    echo "apt-cacher-ng is active with normal upstream access"
  BASH
end

private def report_deb_cache_verification_stage(
  index : Int32,
  title : String,
  progress : Proc(String, Nil)?,
  &block : -> String
) : Nil
  label = "[#{index}/5] #{title}"
  started_at = Time.instant
  report_deb_cache_verification_progress(progress, "#{label} ...")

  begin
    details = yield
  rescue ex
    elapsed = Time.instant - started_at
    report_deb_cache_verification_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
    raise "Failed during #{title}: #{ex.message}"
  end

  elapsed = Time.instant - started_at
  report_deb_cache_verification_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
  report_deb_cache_verification_progress(progress, details) unless details.empty?
end

private def run_deb_cache_verification_command(
  command : String,
  timeout : Time::Span = 30.seconds
) : String
  result = @interaction.execute(command, timeout)
  unless result.success?
    raise "Guest command failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end

  [result.stdout.strip, result.stderr.strip].reject(&.empty?).join("\n")
end

private def report_deb_cache_verification_progress(
  progress : Proc(String, Nil)?,
  message : String
) : Nil
  if callback = progress
    callback.call(message)
  else
    Log.info { message }
  end
end
