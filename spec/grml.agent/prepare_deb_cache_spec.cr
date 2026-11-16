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
  property stdout = "Cache directory: /mnt/shared/deb-cache/proxy\nCached .deb files: 0\nCache size: 4.0K\nAPT proxy: http://127.0.0.1:3142\n"
  property stderr = ""

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    @commands << command
    @timeouts << timeout
    QEMU::CommandResult.new(@exit_code, @stdout, @stderr)
  end
end

class GRMLDebCacheHarness
  getter interaction : GRMLDebCacheFakeInteraction

  include GRML::Agent::PrepareDebCache

  def initialize(@interaction : GRMLDebCacheFakeInteraction)
    @vm = GRMLDebCacheFakeVM.new
  end
end

describe GRML::Agent::PrepareDebCache do
  it "stores apt-cacher-ng data on the shared directory and configures GRML to use it" do
    interaction = GRMLDebCacheFakeInteraction.new
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    agent.prepare_deb_cache(->(message : String) { progress << message; nil })

    interaction.commands.size.should eq(1)
    command = interaction.commands.first
    command.should contain("mountpoint -q /mnt/shared")
    command.should contain("apt-get install -y --no-install-recommends apt-cacher-ng")
    command.should contain("CacheDir: /mnt/shared/deb-cache/proxy")
    command.should contain("BindAddress: 127.0.0.1")
    command.should contain("Acquire::http::Proxy")
    command.should contain("export APT_PROXY")
    command.should contain("service apt-cacher-ng restart")
    command.should contain("acng-report.html")
    interaction.timeouts.should eq([5.minutes])
    progress.last.should contain("source /etc/profile.d/90-grml-agent-deb-cache.sh")
  end

  it "reports setup failures instead of claiming the cache is ready" do
    interaction = GRMLDebCacheFakeInteraction.new
    interaction.exit_code = 21
    interaction.stderr = "apt-cacher-ng did not become ready"
    agent = GRMLDebCacheHarness.new(interaction)
    progress = [] of String

    error = expect_raises(Exception, "Could not prepare shared Debian package cache") do
      agent.prepare_deb_cache(->(message : String) { progress << message; nil })
    end

    error.message.should contain("apt-cacher-ng did not become ready")
    progress.last.should eq("Shared Debian package cache setup failed")
  end
end
