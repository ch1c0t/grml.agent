private def checkout_grml_live_command(ref : String) : String
  <<-SHELL
    set -eu
    if [ ! -d '#{GRML_LIVE_CHECKOUT}/.git' ]; then
      echo "[git] Cloning grml-live repository"
      rm -rf '#{GRML_LIVE_CHECKOUT}'
      git clone --filter=blob:none --no-checkout https://github.com/grml/grml-live.git '#{GRML_LIVE_CHECKOUT}'
    fi
    echo "[git] Fetching ref: #{ref}"
    git -C '#{GRML_LIVE_CHECKOUT}' fetch --progress --force --depth=1 origin '#{ref}'
    echo "[git] Checking out fetched commit"
    git -C '#{GRML_LIVE_CHECKOUT}' checkout --force --detach FETCH_HEAD
    git -C '#{GRML_LIVE_CHECKOUT}' clean -fdx
    git -C '#{GRML_LIVE_CHECKOUT}' rev-parse HEAD
  SHELL
end
