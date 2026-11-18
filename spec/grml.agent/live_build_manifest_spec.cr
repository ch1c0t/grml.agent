require "spec"
require "../../src/logger"
require "../../src/grml"

describe GRML::LiveBuildManifest do
  it "parses build settings and produces the class argument expected by grml-live" do
    manifest = GRML::LiveBuildManifest.from_json(%({
      "suite": "trixie",
      "classes": ["GRML_SMALL", "NO_ONLINE", "RESCUE"],
      "hostname": "rescue-system",
      "username": "operator",
      "distri_name": "rescue",
      "distri_info": "Custom GRML rescue environment",
      "grml_name": "rescue",
      "release_name": "Rescue image",
      "version": "0.1.0",
      "boot_options": ["ssh", "net.ifnames=0"],
      "secure_boot": false,
      "release": false,
      "bootstrap_mirror_url": "http://deb.debian.org/debian",
      "grml_live_ref": "master",
      "iso_name": "rescue_0.1.0.iso",
      "date": "2026-11-18",
      "wayback_date": "20261101",
      "source_date_epoch": 1794950400
    }))

    manifest.validate!
    manifest.classes_argument.should eq("GRML_SMALL,NO_ONLINE,RESCUE")
    manifest.boot_options.join(" ").should eq("ssh net.ifnames=0")
    manifest.release.should be_false
    manifest.iso_name.should eq("rescue_0.1.0.iso")
    manifest.wayback_date.should eq("20261101")
  end

  it "uses useful defaults for an omitted optional setting" do
    manifest = GRML::LiveBuildManifest.from_json(%({"classes":["GRML_SMALL"]}))

    manifest.validate!
    manifest.suite.should eq("trixie")
    manifest.grml_live_ref.should eq("master")
    manifest.bootstrap_mirror_url.should eq("http://deb.debian.org/debian")
    manifest.release.should be_true
  end

  it "rejects classes that grml-live selects automatically" do
    manifest = GRML::LiveBuildManifest.from_json(%({"classes":["GRMLBASE"]}))

    expect_raises(ArgumentError, "added automatically") do
      manifest.validate!
    end
  end

  it "rejects Debian classes that grml-live selects automatically" do
    manifest = GRML::LiveBuildManifest.from_json(%({"classes":["DEBIAN_TRIXIE"]}))

    expect_raises(ArgumentError, "added automatically") do
      manifest.validate!
    end
  end

  it "rejects duplicate or malformed class names" do
    duplicate = GRML::LiveBuildManifest.from_json(%({"classes":["RESCUE","RESCUE"]}))
    expect_raises(ArgumentError, "Duplicate grml-live class") { duplicate.validate! }

    unsafe = GRML::LiveBuildManifest.from_json(%({"classes":["RESCUE; touch /tmp/pwned"]}))
    expect_raises(ArgumentError, "Invalid grml-live class name") { unsafe.validate! }
  end

  it "rejects unsafe image names, refs, and boot options" do
    unsafe_image = GRML::LiveBuildManifest.from_json(%({"iso_name":"../rescue.iso"}))
    expect_raises(ArgumentError, "iso_name must be a filename") { unsafe_image.validate! }

    unsafe_ref = GRML::LiveBuildManifest.from_json(%({"grml_live_ref":"../../main"}))
    expect_raises(ArgumentError, "Invalid grml_live_ref") { unsafe_ref.validate! }

    unsafe_options = GRML::LiveBuildManifest.from_json(%({"boot_options":["ssh\\nrm -rf /"]}))
    expect_raises(ArgumentError, "Invalid boot option") { unsafe_options.validate! }

    unsafe_snapshot = GRML::LiveBuildManifest.from_json(%({"wayback_date":"2026-11-01"}))
    expect_raises(ArgumentError, "wayback_date must use") { unsafe_snapshot.validate! }
  end
end
