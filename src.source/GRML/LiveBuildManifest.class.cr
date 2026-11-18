  property suite : String = "trixie"
  property classes : Array(String) = ["GRML_SMALL"]
  property hostname : String = "grml"
  property username : String = "grml"
  property distri_name : String = "grml"
  property distri_info : String = "Custom Grml Live Linux system"
  property grml_name : String = "grml"
  property release_name : String = "custom"
  property version : String = "0.1.0"
  property boot_options : Array(String) = [] of String
  property secure_boot : Bool = false
  property release : Bool = true
  property bootstrap_mirror_url : String = "http://deb.debian.org/debian"
  property grml_live_ref : String = "master"
  property iso_name : String? = nil
  property date : String? = nil
  property source_date_epoch : Int64? = nil

  def self.from_json(source : String) : self
    data = JSON.parse(source).as_h

    classes = data["classes"]?.try(&.as_a.map(&.as_s)) || ["GRML_SMALL"]
    boot_options = data["boot_options"]?.try(&.as_a.map(&.as_s)) || [] of String

    new(
      suite: data["suite"]?.try(&.as_s) || "trixie",
      classes: classes,
      hostname: data["hostname"]?.try(&.as_s) || "grml",
      username: data["username"]?.try(&.as_s) || "grml",
      distri_name: data["distri_name"]?.try(&.as_s) || "grml",
      distri_info: data["distri_info"]?.try(&.as_s) || "Custom Grml Live Linux system",
      grml_name: data["grml_name"]?.try(&.as_s) || "grml",
      release_name: data["release_name"]?.try(&.as_s) || "custom",
      version: data["version"]?.try(&.as_s) || "0.1.0",
      boot_options: boot_options,
      secure_boot: data["secure_boot"]?.try(&.as_bool) || false,
      release: data["release"]?.try(&.as_bool) != false,
      bootstrap_mirror_url: data["bootstrap_mirror_url"]?.try(&.as_s) || "http://deb.debian.org/debian",
      grml_live_ref: data["grml_live_ref"]?.try(&.as_s) || "master",
      iso_name: data["iso_name"]?.try(&.as_s?),
      date: data["date"]?.try(&.as_s?),
      source_date_epoch: data["source_date_epoch"]?.try(&.as_i64?)
    )
  end

  def initialize(
    @suite : String = "trixie",
    @classes : Array(String) = ["GRML_SMALL"],
    @hostname : String = "grml",
    @username : String = "grml",
    @distri_name : String = "grml",
    @distri_info : String = "Custom Grml Live Linux system",
    @grml_name : String = "grml",
    @release_name : String = "custom",
    @version : String = "0.1.0",
    @boot_options : Array(String) = [] of String,
    @secure_boot : Bool = false,
    @release : Bool = true,
    @bootstrap_mirror_url : String = "http://deb.debian.org/debian",
    @grml_live_ref : String = "master",
    @iso_name : String? = nil,
    @date : String? = nil,
    @source_date_epoch : Int64? = nil
  )
  end

  BUILTIN_CLASSES = %w(
    DEBORPHAN FRESHCLAM GRML_FULL GRML_GHACI GRML_GHACI_CLOUD GRML_SMALL
    LATEX LATEX_CLEANUP LOCALES NO_ONLINE REMOVE_DOCS SOURCES TOR XORG ZFS
  )

  RESERVED_CLASSES = %w(GRMLBASE SECURE_BOOT RELEASE AMD64 ARM64 I386)

  def validate! : Nil
    validate_token(suite, "suite")
    validate_token(hostname, "hostname")
    validate_token(username, "username")
    validate_token(distri_name, "distri_name")
    validate_token(grml_name, "grml_name")
    validate_token(version, "version")

    unless grml_live_ref.matches?(/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/) &&
           !grml_live_ref.split('/').includes?("..")
      raise ArgumentError.new("Invalid grml_live_ref: #{grml_live_ref.inspect}")
    end

    unless bootstrap_mirror_url.matches?(/\Ahttps?:\/\/[^\s]+\z/)
      raise ArgumentError.new("bootstrap_mirror_url must be an HTTP(S) URL")
    end

    if classes.empty?
      raise ArgumentError.new("At least one grml-live class must be selected")
    end

    seen = Set(String).new
    classes.each do |class_name|
      unless class_name.matches?(/\A[A-Z][A-Z0-9_]*\z/)
        raise ArgumentError.new("Invalid grml-live class name: #{class_name.inspect}")
      end
      if RESERVED_CLASSES.includes?(class_name) || class_name.starts_with?("DEBIAN_")
        raise ArgumentError.new("Class #{class_name} is added automatically by grml-live and must not be requested")
      end
      if seen.includes?(class_name)
        raise ArgumentError.new("Duplicate grml-live class: #{class_name}")
      end
      seen.add(class_name)
    end

    boot_options.each do |option|
      if option.empty? || option.bytesize > 256 || option.includes?('\n') || option.includes?('\r') || option.includes?('\0')
        raise ArgumentError.new("Invalid boot option: #{option.inspect}")
      end
    end

    if boot_options.join(" ").bytesize > 1024
      raise ArgumentError.new("Combined boot options exceed 1024 bytes")
    end

    validate_display_text(distri_info, "distri_info", 512)
    validate_display_text(release_name, "release_name", 128)

    if name = iso_name
      unless name.ends_with?(".iso") && name.matches?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\.iso\z/)
        raise ArgumentError.new("iso_name must be a filename ending in .iso")
      end
    end

    if build_date = date
      unless build_date.matches?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
        raise ArgumentError.new("date must use YYYY-MM-DD format")
      end
    end

    if epoch = source_date_epoch
      raise ArgumentError.new("source_date_epoch must be a positive Unix timestamp") unless epoch > 0
    end
  end

  def classes_argument : String
    classes.join(",")
  end

  private def validate_token(value : String, label : String) : Nil
    unless value.matches?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
      raise ArgumentError.new("Invalid #{label}: #{value.inspect}")
    end
  end

  private def validate_display_text(value : String, label : String, max_bytes : Int32) : Nil
    if value.empty? || value.bytesize > max_bytes || value.includes?('\n') || value.includes?('\r') || value.includes?('\0')
      raise ArgumentError.new("Invalid #{label}")
    end
  end
