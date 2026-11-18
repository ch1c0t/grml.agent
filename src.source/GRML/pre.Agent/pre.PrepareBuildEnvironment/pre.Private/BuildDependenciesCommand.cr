private def build_dependencies_command(packages : Array(String)) : String
  <<-SHELL
    set -eu
    echo "[apt] Updating package indexes"
    apt-get update
    echo "[apt] Installing #{packages.size} packages"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}
    echo "[apt] Build dependencies are installed"
  SHELL
end
