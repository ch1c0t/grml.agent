require "spec"
require "../../src/logger"
require "../../src/grml"

class GRMLDebCacheFakeVM
  getter shared_path : String

  def initialize(@shared_path : String = "/shared")
  end
end

class GRMLDebCacheFakeInteraction
  getter commands = [] of String
  getter timeouts = [] of Time::Span
  property exit_code = 0
  property failure_at : Int32?
  property failure_exit_code = 1
  property stdout = ""
  property stderr = ""

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    @commands << command
    @timeouts << timeout
    code = @failure_at == @commands.size ? @failure_exit_code : @exit_code
    QEMU::CommandResult.new(code, @stdout, @stderr)
  end
end

class GRMLDebCacheHarness
  getter interaction : GRMLDebCacheFakeInteraction

  include GRML::Agent::PrepareDebCache
  include GRML::Agent::VerifyDebCache

  def initialize(@interaction : GRMLDebCacheFakeInteraction)
    @vm = GRMLDebCacheFakeVM.new
  end
end

describe GRML::Agent::PrepareDebCache do
  it "prepares shared storage, configures the proxy, and reports each completed stage" do
    interaction = GRMLDebCacheFakeInteraction.new
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    agent.prepare_deb_cache(->(message : String) { progress << message; nil })

    interaction.commands.size.should eq(7)
    interaction.commands[0].should contain("mountpoint -q /mnt/shared")
    interaction.commands[0].should contain("mktemp /mnt/shared/")
    interaction.commands[1].should contain("dpkg-query -W -f='${Status}")
    interaction.commands[1].should contain("apt-cacher-ng")
    interaction.commands[1].should contain("Acquire::http::Proxy=DIRECT")
    interaction.commands[2].should contain("printf '%s\\n'")
    interaction.commands[2].should_not contain("<<'EOF'")
    interaction.commands[2].should contain("'CacheDir: /mnt/shared/deb-cache/proxy'")
    interaction.commands[2].should contain("'BindAddress: 127.0.0.1'")
    interaction.commands[2].should contain("'ReportPage: acng-report.html'")
    interaction.commands[2].should contain("zzzz-grml-agent.conf")
    interaction.commands[2].should contain("BindAddress: 127.0.0.1")
    interaction.commands[2].should contain("ReportPage: acng-report.html")
    interaction.commands[2].should contain("runuser -u apt-cacher-ng -- test -w")
    interaction.commands[2].should contain("ConditionPathIsMountPoint=/mnt/shared")
    interaction.commands[2].should_not contain("WorkingDirectory=/mnt/shared/deb-cache/proxy")
    interaction.commands[2].should contain("ReadWritePaths=/mnt/shared/deb-cache/proxy")
    interaction.commands[3].should contain("printf '%s\\n'")
    interaction.commands[3].should_not contain("<<'EOF'")
    interaction.commands[3].should contain("Acquire::http::Proxy \"http://127.0.0.1:3142\";")
    interaction.commands[3].should contain("export APT_PROXY=\"http://127.0.0.1:3142\"")
    interaction.commands[3].should contain("/etc/environment")
    interaction.commands[4].should contain("rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'")
    interaction.commands[4].should contain("systemctl daemon-reload")
    interaction.commands[4].should contain("systemctl restart apt-cacher-ng.service")
    interaction.commands[4].should contain("diagnose_start_failure")
    interaction.commands[4].should contain("systemctl --no-pager --full status")
    interaction.commands[4].should contain("journalctl -u apt-cacher-ng.service")
    interaction.commands[4].should contain("tail -n 80")
    interaction.commands[5].should contain("acng-report.html")
    interaction.commands[5].should contain("journalctl -u apt-cacher-ng")
    interaction.commands[6].should contain("find \"$cache_path\" -type f -name '*.deb'")
    interaction.timeouts.should eq([
      30.seconds,
      5.minutes,
      30.seconds,
      30.seconds,
      45.seconds,
      30.seconds,
      30.seconds,
    ])
    progress.any? { |message| message.includes?("[1/7] Checking the shared directory done") }.should be_true
    progress.any? { |message| message.includes?("[7/7] Reporting cache status done") }.should be_true
    progress.any? { |message| message.includes?("Package reuse is not yet verified") }.should be_true
    progress.last.should contain("Total preparation time:")
  end

  it "includes service diagnostics when apt-cacher-ng cannot start" do
    interaction = GRMLDebCacheFakeInteraction.new
    interaction.failure_at = 5
    interaction.stderr = "Job for apt-cacher-ng.service failed"
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    error = expect_raises(Exception, "Failed during Starting apt-cacher-ng") do
      agent.prepare_deb_cache(->(message : String) { progress << message; nil })
    end

    error.message.to_s.should contain("Job for apt-cacher-ng.service failed")
    interaction.commands[4].should contain("journalctl -u apt-cacher-ng.service")
    progress.last.should contain("[5/7] Starting apt-cacher-ng FAILED")
    progress.any? { |message| message == "Shared Debian package cache is ready" }.should be_false
  end

  it "reports the failing setup stage without claiming the cache is ready" do
    interaction = GRMLDebCacheFakeInteraction.new
    interaction.exit_code = 20
    interaction.stderr = "The QEMU shared directory is not mounted"
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    error = expect_raises(Exception, "Failed during Checking the shared directory") do
      agent.prepare_deb_cache(->(message : String) { progress << message; nil })
    end

    error.message.to_s.should contain("The QEMU shared directory is not mounted")
    progress.last.should contain("[1/7] Checking the shared directory FAILED")
    progress.any? { |message| message == "Shared Debian package cache is ready" }.should be_false
  end
end

describe GRML::Agent::VerifyDebCache do
  it "downloads the same package version again with upstream access disabled and restores normal mode" do
    interaction = GRMLDebCacheFakeInteraction.new
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    agent.verify_deb_cache("hello", ->(message : String) { progress << message; nil })

    interaction.commands.size.should eq(6)
    interaction.commands[0].should contain("Acquire::http::Proxy")
    interaction.commands[0].should contain("rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'")
    interaction.commands[1].should contain("apt-get update")
    interaction.commands[1].should contain("apt-cache policy")
    interaction.commands[1].should contain("apt-get download")
    interaction.commands[1].should contain("sha256sum")
    interaction.commands[2].should contain("printf '%s\\n' 'Offlinemode: 1'")
    interaction.commands[2].should_not contain("<<'EOF'")
    interaction.commands[2].should contain("systemctl restart apt-cacher-ng")
    interaction.commands[3].should contain("apt-get download")
    interaction.commands[3].should contain("sha256sum")
    interaction.commands[4].should contain("rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'")
    interaction.commands[5].should contain("rm -rf '/tmp/grml-agent-deb-cache-verify-")
    progress.any? { |message| message.includes?("Fetching the same version with upstream disabled done") }.should be_true
    progress.any? { |message| message.includes?("Shared Debian package cache verified for hello") }.should be_true
  end

  it "restores normal proxy mode if the offline download fails" do
    interaction = GRMLDebCacheFakeInteraction.new
    interaction.failure_at = 4
    interaction.stderr = "package was not available offline"
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    expect_raises(Exception, "Failed during Fetching the same version with upstream disabled") do
      agent.verify_deb_cache("hello", ->(message : String) { progress << message; nil })
    end

    interaction.commands.size.should eq(6)
    interaction.commands[4].should contain("rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'")
    interaction.commands[5].should contain("rm -rf '/tmp/grml-agent-deb-cache-verify-")
    progress.any? { |message| message.includes?("Restored normal apt-cacher-ng mode after verification failure") }.should be_true
  end

  it "rejects unsafe package names before executing guest commands" do
    interaction = GRMLDebCacheFakeInteraction.new
    agent = GRMLDebCacheHarness.new(interaction)

    expect_raises(ArgumentError, "Invalid Debian package name") do
      agent.verify_deb_cache("hello; touch /tmp/pwned")
    end

    interaction.commands.should be_empty
  end
end
