require "file_utils"

module ProfileExecutableSpecFixture
  def self.build(host : String?) : Tuple(ProfileExecutableSpecAgent, String)
    root = File.join(Dir.tempdir, "grml-profile-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
    profile = File.join(root, "profiles", "rescue")
    Dir.mkdir_p(profile)
    File.write(File.join(profile, "packages.txt"), "")
    File.write(File.join(profile, "host-executables.txt"), "mitamae https://example.invalid/mitamae\n")
    {ProfileExecutableSpecAgent.new(root, host), root}
  end

  def self.remove(root : String) : Nil
    FileUtils.rm_rf(root)
  end
end
