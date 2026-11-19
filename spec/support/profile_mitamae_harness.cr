class ProfileMitamaeSpecVM
  getter shared_path : String
  def initialize(@shared_path : String); end
end

class ProfileMitamaeSpecInteraction
  getter commands = [] of String
  def execute_streaming(command : String, timeout : Time::Span = 30.seconds, &block : Symbol, String ->) : QEMU::CommandResult
    @commands << command
    QEMU::CommandResult.new(0, "", "")
  end
end

class ProfileMitamaeSpecAgent
  include GRML::Agent::ApplyProfile
  getter interaction : ProfileMitamaeSpecInteraction

  def initialize(shared_path : String)
    @vm = ProfileMitamaeSpecVM.new(shared_path)
    @interaction = ProfileMitamaeSpecInteraction.new
  end

  private def read_profile_packages(name : String, progress : Proc(String, Nil)?) : Array(String); [] of String; end
  private def profile_host_executables(name : String) : Array(Tuple(String, String)); [] of Tuple(String, String); end
  private def install_profile_host_executables(entries : Array(Tuple(String, String)), progress : Proc(String, Nil)?) : Nil; end
  private def apply_profile_packages(name : String, packages : Array(String), progress : Proc(String, Nil)?) : Nil; end
  private def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil; end
  private def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil; end
end
