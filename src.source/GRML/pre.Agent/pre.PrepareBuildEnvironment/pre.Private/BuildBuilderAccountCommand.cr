private def build_builder_account_command : String
  <<-SHELL
    set -eu
    echo "[account] Ensuring #{GRML_LIVE_BUILDER} exists"
    id '#{GRML_LIVE_BUILDER}' >/dev/null 2>&1 ||
      useradd --create-home --user-group --shell /bin/bash '#{GRML_LIVE_BUILDER}'
    echo "[account] Ensuring subordinate UID/GID ranges"
    #{build_subordinate_id_command}
    echo "[account] Testing user namespace mappings"
    runuser -u '#{GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
    echo "[account] User namespace mappings are usable"
  SHELL
end
