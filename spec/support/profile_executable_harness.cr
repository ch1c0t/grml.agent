class ProfileExecutableSpecVM
  getter shared_path : String
  def initialize(@shared_path : String); end
end

class ProfileExecutableSpecInteraction
  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    QEMU::CommandResult.new(0, "", "")
  end
  def execute_streaming(command : String, timeout : Time::Span = 30.seconds, &block : Symbol, String ->) : QEMU::CommandResult
    QEMU::CommandResult.new(0, "", "")
  end
end

class ProfileExecutableSpecAgent
  include GRML::Agent::ApplyProfile
  getter copied = [] of Tuple(String, String)
  getter downloads = [] of String
  def initialize(shared_path : String, @host : String?)
    @vm = ProfileExecutableSpecVM.new(shared_path)
    @interaction = ProfileExecutableSpecInteraction.new
  end
  private def find_profile_host_executable(name : String) : String?; @host; end
  private def download_profile_executable(name : String, url : String) : String
    @downloads << url
    path = File.join(@vm.shared_path, "downloaded-mitamae")
    File.write(path, "binary")
    path
  end
  def copy_executable_to_guest(source : String, destination : String) : Nil
    @copied << {source, destination}
  end
  def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil; end
  def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil; end
end
