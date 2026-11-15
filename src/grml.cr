require "qemu"
require "tmux_repl"

module GRML

  class Agent
    module Boot
      def boot : Nil
        navigate_boot_menu
        wait_for_shell
        verify_guest_agent
        configure_console
        verify_shared_directory
      
        Log.info { "GRML shared directory is operational" }
      end
      
      private def navigate_boot_menu : Nil
        Log.info { "Waiting for GRML boot prompt" }
        @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
        Log.info { "Sending Return to GRML boot prompt" }
        @vm.send_key("ret")
      
        Log.info { "Waiting for GRML key prompt" }
        @interaction.wait_for_text("Press a key", region: :bottom_tenth)
        Log.info { "Sending Return to GRML key prompt" }
        @vm.send_key("ret")
      end
      
      private def wait_for_shell : Nil
        Log.info { "Waiting for GRML shell prompt" }
        @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
      end
      
      private def verify_guest_agent : Nil
        Log.info { "GRML command line ready; checking QEMU Guest Agent" }
        result = @interaction.execute("printf 'qemu-guest-agent-ok\\n'")
        unless result.success? && result.stdout.strip == "qemu-guest-agent-ok"
          raise "QEMU Guest Agent test failed (exit=#{result.exit_code}, stdout=#{result.stdout.inspect}, stderr=#{result.stderr.inspect})"
        end
        Log.info { "QEMU Guest Agent is operational" }
      end
      
      private def configure_console : Nil
        Log.info { "Setting GRML console font size to 12x24" }
        result = @interaction.execute("sed -i 's|^FONTSIZE=.*|FONTSIZE=\"12x24\"|' /etc/default/console-setup && grep -Fqx 'FONTSIZE=\"12x24\"' /etc/default/console-setup && setupcon")
        unless result.success?
          raise "Could not configure GRML console font size (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
        Log.info { "GRML console font size set to 12x24" }
      end
    end
  
    module PrepareAlpineBundle
      def prepare_alpine_bundle(branch : String = "latest-stable", progress : Proc(String, Nil)? = nil) : Nil
        run = GRML::AlpineBundleRun.new(
          branch,
          @vm.shared_path,
          Time.utc,
          Random.rand(0_i64..Int64::MAX)
        )
        bundle = run.directory
        repository = run.repository_root
        packages = run.packages_directory
        tools = run.tools_directory
        keys = run.keys_directory
        arch = GRML::AlpineBundleRun::ARCHITECTURE
        apk_root = run.apk_root
        mirror = "https://dl-cdn.alpinelinux.org/alpine"
        started_at = Time.instant
      
        report_bundle_progress(progress, "Preparing Alpine offline bundle")
        report_bundle_progress(progress, "Alpine branch: #{branch}")
        report_bundle_progress(progress, "Run ID: #{run.run_id}")
        report_bundle_progress(progress, "Bundle directory: #{run.host_directory}")
        report_bundle_progress(progress, "LATEST pointer: #{run.host_latest_pointer}")
      
        report_bundle_stage(1, "Checking GRML architecture", progress) do
          verify_bundle_architecture
        end
      
        report_bundle_stage(2, "Creating an isolated bundle run directory", progress) do
          run_bundle_command(
            "mkdir -p '#{run.runs_root}' && " +
            "mkdir '#{bundle}' && " +
            "mkdir -p '#{tools}' '#{keys}' '#{packages}' '#{apk_root}' && " +
            "printf 'run_id=%s\\n' '#{run.run_id}' > '#{bundle}/RUNNING'"
          )
        end
      
        report_bundle_stage(3, "Downloading and verifying alpine-chroot-install", progress) do
          run_bundle_command(
            "cd '#{tools}' && curl -fsSL " +
            "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/v0.14.0/alpine-chroot-install " +
            "-o alpine-chroot-install"
          )
          run_bundle_command(
            "cd '#{tools}' && printf '%s  %s\\n' " +
            "a181c3b3ebc2d7eb7e44d0178dd4ba78a2c9d3ae136f9192317e0bf9262fac3b alpine-chroot-install | sha256sum -c -"
          )
        end
      
        report_bundle_stage(4, "Downloading and verifying apk.static", progress) do
          run_bundle_command(
            "cd '#{tools}' && curl -fsSL " +
            "https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.7/x86_64/apk.static " +
            "-o apk.static"
          )
          run_bundle_command(
            "cd '#{tools}' && printf '%s  %s\\n' " +
            "bdd044e0fd6cc388c5e571e1093efa5f35f7767cc5aa338b0a2576a429009a62 apk.static | sha256sum -c -"
          )
          run_bundle_command("chmod +x '#{tools}/apk.static'")
        end
      
        report_bundle_stage(5, "Extracting and installing Alpine signing keys", progress) do
          extract_alpine_keys(tools, keys)
          run_bundle_command("mkdir -p '#{apk_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{apk_root}/etc/apk/keys/'")
        end
      
        report_bundle_stage(6, "Fetching Alpine packages from main and community", progress) do
          fetch_alpine_packages(packages, apk_root, tools, mirror, branch)
        end
      
        report_bundle_stage(7, "Verifying downloaded APK package signatures", progress) do
          run_bundle_command(run.package_verification_command)
        end
      
        report_bundle_stage(8, "Building the local APK repository index for x86_64", progress) do
          run_bundle_command(run.repository_index_command)
        end
      
        report_bundle_stage(9, "Checking the local APK repository", progress) do
          inspect_local_repository(bundle, repository, packages, progress)
        end
      
        report_bundle_stage(10, "Verifying offline installation", progress) do
          verify_offline_repository(repository, bundle, tools, keys, arch)
        end
      
        report_bundle_stage(11, "Writing bundle manifest and SHA-256 checksums", progress) do
          run_bundle_command(run.write_manifest_command(branch))
        end
      
        report_bundle_stage(12, "Verifying bundle manifest and every checksum", progress) do
          run_bundle_command(run.verify_manifest_command(branch))
        end
      
        report_bundle_stage(13, "Marking the verified run COMPLETE", progress) do
          run_bundle_command(run.complete_marker_command)
        end
      
        report_bundle_stage(14, "Publishing the LATEST bundle pointer", progress) do
          run_bundle_command(run.publish_latest_command)
        end
      
        elapsed = Time.instant - started_at
        report_bundle_progress(progress, "Prepared Alpine offline bundle: #{run.host_directory}")
        report_bundle_progress(progress, "LATEST now contains: #{run.latest_pointer_contents}")
        report_bundle_progress(progress, "Total preparation time: #{elapsed.total_seconds.round(1)}s")
      end
      
      private def report_bundle_stage(
        index : Int32,
        title : String,
        progress : Proc(String, Nil)?,
        &block : -> Nil
      ) : Nil
        label = "[#{index}/14] #{title}"
        started_at = Time.instant
        report_bundle_progress(progress, "#{label} ...")
      
        begin
          yield
        rescue ex
          elapsed = Time.instant - started_at
          report_bundle_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
          raise "Failed during #{title}: #{ex.message}"
        end
      
        elapsed = Time.instant - started_at
        report_bundle_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
      end
      
      private def report_bundle_progress(progress : Proc(String, Nil)?, message : String) : Nil
        if callback = progress
          callback.call(message)
        else
          Log.info { message }
        end
      end
      
      private def verify_bundle_architecture : Nil
        result = @interaction.execute("uname -m")
        raise "Could not detect GRML CPU architecture" unless result.success?
        unless result.stdout.strip == "x86_64"
          raise "Alpine bundle preparation currently supports x86_64 only (found #{result.stdout.strip.inspect})"
        end
      end
      
      private def extract_alpine_keys(tools : String, keys : String) : Nil
        script = "#{tools}/alpine-chroot-install"
        command = "awk '/^ALPINE_KEYS=/,/^\\x27$/ { if (NR > 1 && $0 !~ /^ALPINE_KEYS=/ && $0 !~ /^\\x27$/) print }' '#{script}' | " +
          "while IFS= read -r line; do " +
          "id=\${line%%:*}; content=\${line#*:}; " +
          "[ -n \"\${id}\" ] || continue; " +
          "file='#{keys}/alpine-devel@lists.alpinelinux.org-'\${id}'.rsa.pub'; " +
          "printf '%s\\n' '-----BEGIN PUBLIC KEY-----' > \"\${file}\"; " +
          "printf '%b\\n' \"\${content}\" >> \"\${file}\"; " +
          "printf '%s\\n' '-----END PUBLIC KEY-----' >> \"\${file}\"; done"
        run_bundle_command(command)
      end
      
      private def fetch_alpine_packages(packages : String, apk_root : String, tools : String, mirror : String, branch : String) : Nil
        command = "'#{tools}/apk.static' --root '#{apk_root}' --keys-dir '#{apk_root}/etc/apk/keys' --no-cache --arch x86_64 " +
          "--repository #{mirror}/#{branch}/main " +
          "--repository #{mirror}/#{branch}/community " +
          "fetch --recursive --output '#{packages}' alpine-base alpine-keys"
        run_bundle_command(command)
      end
      
      private def inspect_local_repository(bundle : String, repository : String, packages : String, progress : Proc(String, Nil)?) : Nil
        index = "#{packages}/APKINDEX.tar.gz"
        command = "set -eu; " +
          "if [ ! -d '#{packages}' ]; then " +
          "echo 'Missing APK architecture directory: #{packages}' >&2; " +
          "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 41; fi; " +
          "if [ ! -s '#{index}' ]; then " +
          "echo 'Missing or empty APK index: #{index}' >&2; " +
          "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 42; fi; " +
          "package_count=$(find '#{packages}' -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]'); " +
          "if [ \"$package_count\" -eq 0 ]; then " +
          "echo 'No APK package files found in: #{packages}' >&2; " +
          "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 43; fi; " +
          "repository_bytes=$(du -sb '#{repository}' | cut -f1); " +
          "printf 'Repository root: %s\\nAPK architecture directory: %s\\nAPK files: %s\\nRepository size: %s bytes\\nIndex: %s\\n' " +
          "'#{repository}' '#{packages}' \"$package_count\" \"$repository_bytes\" '#{index}'"
      
        result = @interaction.execute(command, 300.seconds)
        unless result.success?
          raise "Local APK repository preflight failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
        end
      
        report_bundle_progress(progress, result.stdout.strip)
      end
      
      private def verify_offline_repository(repository : String, bundle : String, tools : String, keys : String, arch : String) : Nil
        test_root = "#{bundle}/verify-root"
        run_bundle_command("rm -rf '#{test_root}' && mkdir -p '#{test_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{test_root}/etc/apk/keys/'")
        command = "'#{tools}/apk.static' --root '#{test_root}' --keys-dir '#{test_root}/etc/apk/keys' " +
          "--allow-untrusted --no-network --arch #{arch} --repository '#{repository}' " +
          "add --initdb alpine-base alpine-keys && " +
          "test -s '#{test_root}/lib/apk/db/installed' && " +
          "grep -Fqx 'P:alpine-base' '#{test_root}/lib/apk/db/installed' && " +
          "grep -Fqx 'P:alpine-keys' '#{test_root}/lib/apk/db/installed'"
        run_bundle_command(command)
        run_bundle_command("rm -rf '#{test_root}'")
      end
      
      private def run_bundle_command(command : String) : Nil
        result = @interaction.execute(command, 300.seconds)
        unless result.success?
          raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\n#{result.stderr}\n#{result.stdout}"
        end
      end
    end
  
    module Storage
      DISK_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
      DISK_SIZE_PATTERN = /\A[1-9][0-9]*(?:[KMGTP])?\z/i
      DISK_FORMATS = ["qcow2", "raw"]
      
      def create_disk(name : String, size : String, format : String = "qcow2") : String
        path = create_disk_image(name, size, format)
      
        begin
          attach_disk(path, format)
        rescue ex
          File.delete(path) if File.exists?(path)
          raise ex
        end
      
        path
      end
      
      def create_ext4_disk(
        name : String,
        size : String,
        mountpoint : String? = nil,
        format : String = "qcow2"
      ) : String
        validate_disk_name(name)
        validate_disk_format(format)
        guest_mountpoint = validate_guest_mountpoint(mountpoint || "/mnt/#{name}")
      
        path = create_disk_image(name, size, format)
      
        attached = begin
          attach_disk_with_serial(path, format)
        rescue ex
          File.delete(path) if File.exists?(path)
          raise ex
        end
      
        begin
          result = @interaction.execute(
            ext4_provisioning_command(attached[:serial], guest_mountpoint),
            2.minutes
          )
      
          unless result.success?
            details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
            message = "Guest provisioning command exited with status #{result.exit_code}"
            message += ":\n#{details}" unless details.empty?
            raise message
          end
        rescue ex
          raise "Disk image #{path} remains attached as #{attached[:device_id]}, but guest partitioning, ext4 formatting, or mounting failed: #{ex.message}"
        end
      
        "#{path} (ext4 mounted at #{guest_mountpoint})"
      end
      
      def attach_disk(path : String, format : String = "qcow2") : String
        attach_disk_with_serial(path, format)[:device_id]
      end
      
      private def validate_disk_name(name : String) : Nil
        unless name.matches?(DISK_NAME_PATTERN)
          raise ArgumentError.new("Invalid disk name: #{name.inspect}")
        end
      end
      
      private def create_disk_image(name : String, size : String, format : String) : String
        validate_disk_name(name)
      
        unless size.matches?(DISK_SIZE_PATTERN)
          raise ArgumentError.new("Invalid disk size: #{size.inspect}; use e.g. 10G")
        end
        validate_disk_format(format)
      
        directory = File.expand_path("./disks")
        Dir.mkdir_p(directory)
        path = File.join(directory, "#{name}.#{format}")
        raise "Disk already exists: #{path}" if File.exists?(path)
      
        output = IO::Memory.new
        error = IO::Memory.new
        result = Process.run("qemu-img", ["create", "-f", format, path, size], output: output, error: error)
        unless result.success?
          raise "qemu-img failed (#{result.exit_code}): #{error.to_s.strip}"
        end
      
        path
      end
      
      private def attach_disk_with_serial(
        path : String,
        format : String
      ) : NamedTuple(device_id: String, serial: String)
        validate_disk_format(format)
        expanded_path = File.expand_path(path)
        raise "Disk image does not exist: #{expanded_path}" unless File.file?(expanded_path)
      
        suffix = Random.rand(1..Int32::MAX)
        file_node = "grml_disk_file_#{suffix}"
        disk_node = "grml_disk_#{suffix}"
        device_id = "grml_virtio_disk_#{suffix}"
        serial = "grml-#{suffix}"
      
        file_arguments = JSON.parse({
          "driver" => "file",
          "filename" => expanded_path,
          "node-name" => file_node,
          "auto-read-only" => true
        }.to_json).as_h
        format_arguments = JSON.parse({
          "driver" => format,
          "file" => file_node,
          "node-name" => disk_node
        }.to_json).as_h
      
        execute_qmp_checked("blockdev-add", file_arguments)
        begin
          execute_qmp_checked("blockdev-add", format_arguments)
          execute_qmp_checked("device_add", JSON.parse({
            "driver" => "virtio-blk-pci",
            "drive" => disk_node,
            "id" => device_id,
            "serial" => serial
          }.to_json).as_h)
        rescue ex
          begin
            execute_qmp_checked("blockdev-del", {"node-name" => JSON::Any.new(disk_node)})
          rescue
          end
          begin
            execute_qmp_checked("blockdev-del", {"node-name" => JSON::Any.new(file_node)})
          rescue
          end
          raise ex
        end
      
        {device_id: device_id, serial: serial}
      end
      
      private def validate_guest_mountpoint(path : String) : String
        unless path.starts_with?("/") && path != "/" && !path.split("/").any? { |part| part == "." || part == ".." }
          raise ArgumentError.new("Mount point must be an absolute guest path without '.' or '..' components: #{path.inspect}")
        end
        path
      end
      
      private def ext4_provisioning_command(serial : String, mountpoint : String) : String
        disk = shell_quote("/dev/disk/by-id/virtio-#{serial}")
        target = shell_quote(mountpoint)
      
        <<-SCRIPT
          set -eu
          disk=#{disk}
          partition="$disk-part1"
          mountpoint=#{target}
      
          for attempt in $(seq 1 50); do
            [ -b "$disk" ] && break
            sleep 0.1
          done
          if [ ! -b "$disk" ]; then
            echo "Guest block device did not appear: $disk" >&2
            exit 1
          fi
      
          if mountpoint -q "$mountpoint"; then
            echo "Guest mount point is already in use: $mountpoint" >&2
            exit 1
          fi
      
          printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
          blockdev --rereadpt "$disk"
          udevadm settle
      
          for attempt in $(seq 1 50); do
            [ -b "$partition" ] && break
            sleep 0.1
          done
          if [ ! -b "$partition" ]; then
            echo "Guest partition did not appear: $partition" >&2
            exit 1
          fi
      
          mkfs.ext4 -F "$partition"
          mkdir -p "$mountpoint"
          mount -t ext4 "$partition" "$mountpoint"
          findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
          printf 'Mounted %s on %s as ext4\\n' "$partition" "$mountpoint"
        SCRIPT
      end
      
      private def shell_quote(value : String) : String
        "'" + value.gsub("'", "'\\''") + "'"
      end
      
      private def validate_disk_format(format : String) : Nil
        unless DISK_FORMATS.includes?(format)
          raise ArgumentError.new("Unsupported disk format #{format.inspect}; choose qcow2 or raw")
        end
      end
      
      private def execute_qmp_checked(command : String, arguments : Hash(String, JSON::Any)) : JSON::Any
        response = @vm.execute_qmp(command, arguments)
        if error = response.as_h["error"]?
          raise "QMP #{command} failed: #{error}"
        end
        response
      end
    end
  
    module Terminate
      def terminate : Bool
        return true if @terminated
      
        Log.info { "Terminating GRML agent" }
        @terminated = @interaction.terminate
        if @terminated
          Log.info { "GRML agent terminated" }
        else
          Log.error { "GRML agent reported a shutdown failure" }
        end
        @terminated
      end
    end
  
    module VerifySharedDirectory
      def verify_shared_directory : Nil
        token = Random.rand(1_i64..Int64::MAX).to_s
        host_file = File.join(@vm.shared_path, ".qemu-host-check-#{token}")
        guest_host_file = "/mnt/shared/.qemu-host-check-#{token}"
        guest_file = "/mnt/shared/.qemu-guest-check-#{token}"
        File.write(host_file, token)
      
        begin
          verify_guest_mount
          verify_guest_read(guest_host_file, token)
          verify_guest_write(guest_file, token)
          unless File.read(File.join(@vm.shared_path, File.basename(guest_file))) == token
            raise "Guest-created shared file is not visible to the host"
          end
        ensure
          @interaction.execute("unlink #{guest_host_file}")
          @interaction.execute("unlink #{guest_file}")
          File.delete(host_file) if File.exists?(host_file)
        end
      end
      
      private def verify_guest_mount : Nil
        command = "mkdir -p /mnt/shared && (mountpoint -q /mnt/shared || " +
          "mount -t 9p -o trans=virtio,version=9p2000.L shared0 /mnt/shared)"
        result = @interaction.execute(command)
        raise "Could not mount QEMU shared directory at /mnt/shared" unless result.success?
      end
      
      private def verify_guest_read(path : String, expected : String) : Nil
        result = @interaction.execute("cat #{path}")
        unless result.success? && result.stdout.strip == expected
          raise "GRML guest cannot read files from the shared directory"
        end
      end
      
      private def verify_guest_write(path : String, token : String) : Nil
        result = @interaction.execute("printf '%s' #{token} > #{path}")
        raise "GRML guest cannot write to the shared directory" unless result.success?
      end
    end
  
    getter vm : QEMU::VM
    getter interaction : QEMU::Interaction
    
    def initialize(iso_path : String? = nil)
      resolved_iso = QEMU::ISOResolver.resolve("grml", iso_path)
      @vm = QEMU::VM.new(iso_path: resolved_iso)
      Log.info { "Started a QEMU::VM with #{@vm.iso_path}" }
      @interaction = QEMU::Interaction.new(@vm)
      @terminated = false
    end
    
    include Boot
    include VerifySharedDirectory
    include PrepareAlpineBundle
    include Storage
    include Terminate
  end

  class AlpineBundleRun
    ARCHITECTURE = "x86_64"
    
    getter run_id : String
    getter bundle_root : String
    getter runs_root : String
    getter directory : String
    getter repository_root : String
    getter packages_directory : String
    getter tools_directory : String
    getter keys_directory : String
    getter apk_root : String
    getter verify_root : String
    getter host_directory : String
    getter host_latest_pointer : String
    getter latest_pointer_contents : String
    
    def initialize(
      branch : String,
      shared_directory : String,
      timestamp : Time,
      nonce : Int64
    )
      unless branch =~ /\A[a-zA-Z0-9._-]+\z/
        raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}")
      end
      raise ArgumentError.new("Alpine bundle run nonce must not be negative") if nonce < 0
    
      @run_id = "#{branch}-#{timestamp.to_s("%Y%m%dT%H%M%SZ")}-#{nonce.to_s(16)}"
    
      @bundle_root = "/mnt/shared/alpine-bundles"
      @runs_root = "#{@bundle_root}/runs"
      @directory = "#{@runs_root}/#{@run_id}"
      @repository_root = "#{@directory}/repository"
      @packages_directory = "#{@repository_root}/x86_64"
      @tools_directory = "#{@directory}/tools"
      @keys_directory = "#{@directory}/keys"
      @apk_root = "#{@directory}/apk-root"
      @verify_root = "#{@directory}/verify-root"
    
      host_shared_directory = shared_directory.sub(/\/+\z/, "")
      @host_directory = File.join(host_shared_directory, "alpine-bundles", "runs", @run_id)
      @host_latest_pointer = File.join(host_shared_directory, "alpine-bundles", "LATEST")
      @latest_pointer_contents = "runs/#{@run_id}"
    end
    
    # Verify downloaded package signatures independently of the unsigned local index.
    def package_verification_command : String
      "cd '#{@packages_directory}' && '#{@tools_directory}/apk.static' --keys-dir '#{@keys_directory}' verify ./*.apk"
    end
    
    # APK's repository index must describe the architecture directory in which
    # all fetched archives are stored. This rewrites upstream noarch entries too.
    def repository_index_command : String
      index = "#{@packages_directory}/APKINDEX.tar.gz"
      "cd '#{@packages_directory}' && '#{@tools_directory}/apk.static' --keys-dir '#{@keys_directory}' index --rewrite-arch #{ARCHITECTURE} --output '#{index}' *.apk"
    end
    
    # Remove build-only roots, then write a manifest and SHA-256 hashes for every
    # file that belongs to the completed bundle payload.
    def write_manifest_command(branch : String) : String
      "set -eu; cd '#{@directory}' && " +
        "rm -rf apk-root verify-root && " +
        "test -x tools/apk.static && test -s tools/alpine-chroot-install && " +
        "find keys -type f -name '*.rsa.pub' -size +0c | grep -q . && " +
        "test -s repository/#{ARCHITECTURE}/APKINDEX.tar.gz && " +
        "package_count=$(find repository/#{ARCHITECTURE} -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]') && " +
        "test \"$package_count\" -gt 0 && " +
        "repository_bytes=$(du -sb repository | cut -f1) && " +
        "printf 'format=4\\nrun_id=%s\\nalpine_branch=%s\\narchitecture=%s\\nrepositories=main,community\\nrequested_packages=alpine-base,alpine-keys\\nrepository=repository\\nrepository_architecture=%s\\nalpine_chroot_install_version=0.14.0\\napk_tools_version=2.14.7\\npackage_signature_verification=apk-verify\\npackage_signatures=verified\\nindex_signature=unsigned\\noffline_install=passed\\noffline_install_network=disabled\\npackage_count=%s\\nrepository_bytes=%s\\nchecksum_algorithm=sha256\\n' " +
        "'#{@run_id}' '#{branch}' '#{ARCHITECTURE}' '#{ARCHITECTURE}' \"$package_count\" \"$repository_bytes\" > MANIFEST && " +
        "find MANIFEST repository tools keys -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS"
    end
    
    # Audit the marker, manifest, repository contents, and every recorded checksum
    # before the run is promoted from RUNNING to COMPLETE.
    def verify_manifest_command(branch : String) : String
      "set -eu; cd '#{@directory}' && " +
        "test -s RUNNING && test ! -e COMPLETE && " +
        "grep -Fqx 'run_id=#{@run_id}' RUNNING && " +
        "grep -Fqx 'format=4' MANIFEST && " +
        "grep -Fqx 'run_id=#{@run_id}' MANIFEST && " +
        "grep -Fqx 'alpine_branch=#{branch}' MANIFEST && " +
        "grep -Fqx 'architecture=#{ARCHITECTURE}' MANIFEST && " +
        "grep -Fqx 'repository=repository' MANIFEST && " +
        "grep -Fqx 'repository_architecture=#{ARCHITECTURE}' MANIFEST && " +
        "grep -Fqx 'alpine_chroot_install_version=0.14.0' MANIFEST && " +
        "grep -Fqx 'apk_tools_version=2.14.7' MANIFEST && " +
        "grep -Fqx 'repositories=main,community' MANIFEST && " +
        "grep -Fqx 'requested_packages=alpine-base,alpine-keys' MANIFEST && " +
        "grep -Fqx 'package_signature_verification=apk-verify' MANIFEST && " +
        "grep -Fqx 'package_signatures=verified' MANIFEST && " +
        "grep -Fqx 'index_signature=unsigned' MANIFEST && " +
        "grep -Fqx 'offline_install=passed' MANIFEST && " +
        "grep -Fqx 'offline_install_network=disabled' MANIFEST && " +
        "grep -Fqx 'checksum_algorithm=sha256' MANIFEST && " +
        "test -s repository/#{ARCHITECTURE}/APKINDEX.tar.gz && " +
        "test -x tools/apk.static && test -s tools/alpine-chroot-install && " +
        "test ! -e apk-root && test ! -e verify-root && " +
        "find keys -type f -name '*.rsa.pub' -size +0c | grep -q . && " +
        "package_count=$(find repository/#{ARCHITECTURE} -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]') && " +
        "test \"$package_count\" -gt 0 && grep -Fqx \"package_count=$package_count\" MANIFEST && " +
        "repository_bytes=$(du -sb repository | cut -f1) && grep -Fqx \"repository_bytes=$repository_bytes\" MANIFEST && " +
        "expected_paths=$(find MANIFEST repository tools keys -type f | LC_ALL=C sort) && " +
        "recorded_paths=$(cut -c67- SHA256SUMS | LC_ALL=C sort) && " +
        "test \"$expected_paths\" = \"$recorded_paths\" && " +
        "sha256sum -c SHA256SUMS"
    end
    
    def complete_marker_command : String
      "set -eu; cd '#{@directory}' && test -s RUNNING && test ! -e COMPLETE && mv RUNNING COMPLETE"
    end
    
    # Publish LATEST by renaming a temporary file on the same filesystem.
    def publish_latest_command : String
      "set -eu; test -s '#{@directory}/COMPLETE' && " +
        "grep -Fqx 'run_id=#{@run_id}' '#{@directory}/COMPLETE' && " +
        "tmp=$(mktemp '#{@bundle_root}/.LATEST.XXXXXX') && " +
        "trap 'rm -f \"$tmp\"' 0 && " +
        "printf '%s\\n' '#{@latest_pointer_contents}' > \"$tmp\" && " +
        "mv -f \"$tmp\" '#{@bundle_root}/LATEST'"
    end
  end

  module CLI
    def self.run(arguments : Array(String) = ARGV.dup) : Nil
      args = arguments.dup
      command = args.shift?
    
      case command
      when "boot"
        Act::Boot.new(args).run
      when "tmux"
        Act::Tmux.new(args).run
      when "prepare_alpine_bundle"
        Act::PrepareAlpineBundle.new(args).run
      else
        STDERR.puts "Usage: grml.agent boot [--iso PATH] | tmux [--iso PATH] | prepare_alpine_bundle [alpine_branch]"
        exit 1
      end
    end
  
    class Act
      getter arguments : Array(String)
      getter boot_iso_path : String?
      
      def initialize(@arguments : Array(String) = [] of String)
        @boot_iso_path = nil
        validate_arguments
      end
      
      def validate_arguments
      end
      
      def run : Nil
        agent = GRML::Agent.new(@boot_iso_path)
        Signal::INT.trap { agent.terminate && exit }
        Signal::TERM.trap { agent.terminate && exit }
        begin
          agent.boot
          perform(agent)
        ensure
          agent.terminate
        end
      end
      
      protected def perform(agent : GRML::Agent) : Nil
      end
    
      class Boot < Act
        def validate_arguments
          if @arguments.size == 2 && @arguments[0] == "--iso"
            @boot_iso_path = @arguments[1]
          else
            unless @arguments.empty?
              STDERR.puts "Usage: grml.agent boot [--iso PATH]"
              exit 1
            end
          end
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "GRML agent is running. Starting REPL." }
          GRML::REPL.run(agent)
        end
      end
    
      class PrepareAlpineBundle < Act
        @branch : String = "latest-stable"
        
        def validate_arguments
          if @arguments.size > 1
            STDERR.puts "Usage: grml.agent prepare_alpine_bundle [alpine_branch]"
            exit 1
          end
        
          @branch = @arguments.first? || "latest-stable"
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          agent.prepare_alpine_bundle(@branch)
        end
      end
    
      class Tmux < Act
        def validate_arguments
          if @arguments.size == 2 && @arguments[0] == "--iso"
            @boot_iso_path = @arguments[1]
          else
            unless @arguments.empty?
              STDERR.puts "Usage: grml.agent tmux [--iso PATH]"
              exit 1
            end
          end
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "Starting tmux inside the GRML guest" }
          agent.interaction.type("tmux")
          agent.vm.send_key("ret")
          sleep 500.milliseconds
        
          Log.info { "Starting the host-side GRML Tmux REPL" }
          GRML::REPL.run(agent)
        end
      end
    end
  end

  class REPL
    FOCUS_ENV = "GRML_AGENT_REPL_FOCUS"
    DEFAULT_ALPINE_BRANCH = "latest-stable"
    
    def self.focus? : Bool
      value = ENV.fetch(FOCUS_ENV, "true").strip.downcase
      case value
      when "1", "true", "yes", "on" then true
      when "0", "false", "no", "off" then false
      else raise ArgumentError.new("#{FOCUS_ENV} must be a boolean; got #{value.inspect}")
      end
    end
    
    def self.alpine_branch(arguments : Array(String)) : String
      raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]") if arguments.size > 1
      branch = arguments.first? || DEFAULT_ALPINE_BRANCH
      raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}") unless branch =~ /\A[a-zA-Z0-9._-]+\z/
      branch
    end
    
    def self.prepare_alpine_bundle(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
      branch = alpine_branch(arguments)
      agent.prepare_alpine_bundle(branch, progress)
      "Prepared Alpine offline bundle (branch: #{branch})."
    end
    
    def self.build_definition(agent : T) : TmuxREPL::Definition forall T
      TmuxREPL.define("grml") do |repl|
        repl.on_command("ocr") do |context, arguments|
          raise ArgumentError.new("Usage: ocr") unless arguments.empty?
          result = agent.interaction.latest_ocr
          if error = result.error
            raise "OCR failed for frame #{result.timestamp}: #{error}"
          end
          result.text.strip.empty? ? context.puts("(no text recognized)") : context.write(result.text)
        end
    
        repl.on_command("guest_exec") do |context, arguments|
          raise ArgumentError.new("Usage: guest_exec <shell command>") if arguments.empty?
    
          command = arguments.join(" ")
          result = agent.interaction.execute(command, 2.minutes)
          context.write(result.stdout) unless result.stdout.empty?
          context.write(result.stderr) unless result.stderr.empty?
          context.puts("Guest command exited with status #{result.exit_code}") unless result.success?
        end
    
        repl.on_command("prepare_alpine_bundle") do |context, arguments|
          progress = ->(message : String) { context.puts(message) }
          GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
          nil
        end
    
        repl.on_command("create_disk") do |context, arguments|
          unless (2..3).includes?(arguments.size)
            raise ArgumentError.new("Usage: create_disk <name> <size> [qcow2|raw]")
          end
          format = arguments[2]? || "qcow2"
          path = agent.create_disk(arguments[0], arguments[1], format)
          context.puts("Created and attached #{path}")
        end
    
        repl.on_command("attach_disk") do |context, arguments|
          unless (1..2).includes?(arguments.size)
            raise ArgumentError.new("Usage: attach_disk <path> [qcow2|raw]")
          end
          format = arguments[1]? || "qcow2"
          device_id = agent.attach_disk(arguments[0], format)
          context.puts("Attached #{File.expand_path(arguments[0])} as #{device_id}")
        end
    
        repl.on_command("create_ext4_disk") do |context, arguments|
          unless (2..4).includes?(arguments.size)
            raise ArgumentError.new("Usage: create_ext4_disk <name> <size> [mountpoint] [qcow2|raw]")
          end
    
          mountpoint = nil
          format = "qcow2"
          if optional = arguments[2]?
            if optional == "qcow2" || optional == "raw"
              format = optional
            else
              mountpoint = optional
              format = arguments[3]? || "qcow2"
            end
          end
    
          result = agent.create_ext4_disk(arguments[0], arguments[1], mountpoint, format)
          context.puts("Created, partitioned, formatted, and mounted #{result}")
        end
      end
    end
    
    def self.run(agent : Agent) : Nil
      definition = build_definition(agent)
      started = false
    
      Signal::INT.trap do
        begin
          definition.stop if started
        ensure
          agent.terminate
          exit
        end
      end
      Signal::TERM.trap do
        begin
          definition.stop if started
        ensure
          agent.terminate
          exit
        end
      end
    
      begin
        focus = focus?
        definition.start(focus: focus)
        started = true
        if focus
          Log.info { "Host-side GRML REPL started in session 'grml'." }
        else
          Log.info { "Host-side GRML REPL started in session 'grml'; switch to it with: tmux switch-client -t grml" }
        end
        definition.serve
      ensure
        definition.stop if started
      end
    end
  end
end