require "file_utils"
require "./profile_composition_interaction"

class ProfileCompositionSpecVM
  getter shared_path : String
  def initialize(@shared_path : String); end
end

class ProfileCompositionSpecAgent
  include GRML::Agent::ApplyProfile
  getter applied_profiles = [] of String
  def initialize(shared_path : String)
    @vm = ProfileCompositionSpecVM.new(shared_path)
    @interaction = ProfileCompositionSpecInteraction.new
  end
  private def read_profile_packages(name : String, progress : Proc(String, Nil)?) : Array(String); [name]; end
  private def install_profile_packages(name : String, packages : Array(String), progress : Proc(String, Nil)?) : Nil
    @applied_profiles << name
  end
  private def install_profile_host_executables(entries : Array(Tuple(String, String)), progress : Proc(String, Nil)?) : Nil; end
  private def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil; end
  private def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil; end
end

module ProfileCompositionSpecFixture
  def self.build : Tuple(ProfileCompositionSpecAgent, String)
    root = File.join(Dir.tempdir, "profile-composition-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
    Dir.mkdir_p(File.join(root, "profiles"))
    {ProfileCompositionSpecAgent.new(root), root}
  end
  def self.add(root : String, name : String, dependencies : String = "") : Nil
    path = File.join(root, "profiles", name)
    Dir.mkdir_p(path)
    File.write(File.join(path, "profiles.txt"), dependencies)
  end
  def self.remove(root : String) : Nil; FileUtils.rm_rf(root); end
end
