require "file_utils"

module ProfileMitamaeSpecFixture
  def self.build(manifest : String, list_content : String = "recipes/second.rb\n") : Tuple(ProfileMitamaeSpecAgent, String)
    root = File.join(Dir.tempdir, "profile-mitamae-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
    profile = File.join(root, "profiles", "rescue")
    Dir.mkdir_p(File.join(profile, "recipes", "defaults"))
    File.write(File.join(profile, "recipes", "base.rb"), "# base")
    File.write(File.join(profile, "recipes", "second.rb"), "# second")
    File.write(File.join(profile, "recipes", "defaults", "default.rb"), "# default")
    File.write(File.join(profile, "recipes", "steps.list"), list_content)
    File.write(File.join(profile, "mitamae-recipes.txt"), manifest)
    File.write(File.join(profile, "mitamae-node.yml"), "attributes: {}\n")
    {ProfileMitamaeSpecAgent.new(root), root}
  end

  def self.remove(root : String) : Nil
    FileUtils.rm_rf(root)
  end
end
