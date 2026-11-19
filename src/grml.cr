require "json"
require "set"
require "qemu"
require "tmux_repl"

module GRML

  class Agent
    module ApplyProfile
      module Private
        module ApplyProfilePackages
          private def apply_profile_packages(profile_name : String, packages : Array(String),
                                              verify_cache : Bool, progress : Proc(String, Nil)?) : Nil
            if packages.empty?
              message = "Profile '#{profile_name}' contains no packages"
              verify_cache ? report_profile_progress(progress, "#{message}; preparing cache for verification") :
                report_profile_progress(progress, "#{message}; skipping APT cache preparation")
              prepare_deb_cache(progress) if verify_cache
            else
              install_profile_packages(profile_name, packages, progress)
            end
            if verify_cache
              report_profile_progress(progress, "Verifying shared Debian package cache after applying profile '#{profile_name}'")
              verify_deb_cache("hello", progress)
            end
          end
        end
      
        module DownloadProfileExecutable
          private def download_profile_executable(name : String, url : String) : String
            path = File.join(Dir.tempdir, "grml-agent-#{name}-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}")
            begin
              result = Process.run(["curl", "--fail", "--location", "--show-error", "--output", path, url],
                output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
              unless result.success? && File.file?(path) && File.size(path) > 0
                raise "curl failed to download '#{name}' (exit=#{result.exit_code})"
              end
              path
            rescue error
              File.delete(path) if File.exists?(path)
              raise "Could not download host executable '#{name}' from #{url}: #{error.message}"
            end
          end
        end
      
        module FindProfileHostExecutable
          private def find_profile_host_executable(name : String) : String?
            Process.find_executable(name)
          end
        end
      
        module InstallProfileHostExecutables
          private def install_profile_host_executables(entries : Array(Tuple(String, String)), progress : Proc(String, Nil)?) : Nil
            entries.each do |entry|
              name = entry[0]
              destination = "/usr/local/bin/#{name}"
              if source = find_profile_host_executable(name)
                report_profile_progress(progress, "Copying host executable '#{name}' to guest")
                copy_executable_to_guest(source, destination)
              else
                report_profile_progress(progress, "Host executable '#{name}' not found; downloading fallback")
                source = download_profile_executable(name, entry[1])
                begin
                  copy_executable_to_guest(source, destination)
                ensure
                  File.delete(source) if File.exists?(source)
                end
              end
            end
          end
        end
      
        module InstallProfilePackages
          private def install_profile_packages(profile_name : String, packages : Array(String),
                                                progress : Proc(String, Nil)?) : Nil
            report_profile_progress(progress, "Preparing shared Debian package cache for profile '#{profile_name}'")
            prepare_deb_cache(progress)
            report_profile_progress(progress, "Installing #{packages.size} package(s) from profile '#{profile_name}'")
            command = "set -eu; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}"
            result = @interaction.execute_streaming(command, 30.minutes) do |_stream, chunk|
              report_profile_output(progress, chunk)
            end
            unless result.success?
              raise "Could not install packages for profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
            report_profile_progress(progress, "Profile '#{profile_name}' packages installed")
          end
        end
      
        module ProfileHostExecutables
          private def profile_host_executables(profile_name : String) : Array(Tuple(String, String))
            path = File.join(@vm.shared_path, "profiles", profile_name, "host-executables.txt")
            return [] of Tuple(String, String) unless File.file?(path)
          
            entries = [] of Tuple(String, String)
            File.each_line(path) do |line|
              fields = line.sub(/#.*/, "").strip.split
              next if fields.empty?
              unless fields.size == 2 && fields[0].matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._+-]*\z/) &&
                     fields[1].matches?(/\Ahttps:\/\/[^\s]+\z/)
                raise ArgumentError.new("Invalid host-executable entry in #{path}: #{line.inspect}")
              end
              raise ArgumentError.new("Duplicate host executable: #{fields[0]}") if entries.any? { |entry| entry[0] == fields[0] }
              entries << {fields[0], fields[1]}
            end
            entries
          end
        end
      
        module ReadProfilePackages
          private def read_profile_packages(profile_name : String, progress : Proc(String, Nil)?) : Array(String)
            path = "#{DEBIAN_PROFILE_DIRECTORY}/#{profile_name}/packages.txt"
            report_profile_progress(progress, "Reading package list for profile '#{profile_name}'")
            command = <<-SHELL
              set -eu
              packages_file='#{path}'
              if [ ! -f "$packages_file" ]; then
                echo "Package profile not found: $packages_file" >&2
                exit 2
              fi
              awk '
                { sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                  if ($0 == "") next
                  if ($0 !~ /^[a-z0-9][a-z0-9+.-]*$/) {
                    printf "Invalid Debian package name on line %d: %s\\n", NR, $0 > "/dev/stderr"
                    exit 2
                  }
                  print
                }
              ' "$packages_file"
              SHELL
            result = @interaction.execute(command)
            unless result.success?
              raise "Could not read package profile '#{profile_name}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
            result.stdout.lines.map(&.strip).reject(&.empty?).uniq
          end
        end
      
        module ReportProfileProgress
          private def report_profile_output(progress : Proc(String, Nil)?, chunk : String) : Nil
            return if chunk.empty?
            if callback = progress
              callback.call(chunk)
            else
              Log.info { chunk }
            end
          end
          
          private def report_profile_progress(progress : Proc(String, Nil)?, message : String) : Nil
            if callback = progress
              callback.call("#{message}\n")
            else
              Log.info { message }
            end
          end
        end
      
        include ApplyProfilePackages
        include DownloadProfileExecutable
        include FindProfileHostExecutable
        include InstallProfileHostExecutables
        include InstallProfilePackages
        include ProfileHostExecutables
        include ReadProfilePackages
        include ReportProfileProgress
      end
    
      include Private
      
      DEBIAN_PROFILE_DIRECTORY = "/mnt/shared/profiles"
      DEBIAN_PROFILE_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
      
      def apply_profile(profile_name : String, verify_cache : Bool = false,
                        progress : Proc(String, Nil)? = nil) : Nil
        unless profile_name.matches?(DEBIAN_PROFILE_NAME_PATTERN)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
        executables = profile_host_executables(profile_name)
        packages = read_profile_packages(profile_name, progress)
        apply_profile_packages(profile_name, packages, verify_cache, progress)
        install_profile_host_executables(executables, progress)
      end
    end
  
    module Boot
      def boot(profile_name : String? = nil, verify_cache : Bool = false) : Nil
        if verify_cache && profile_name.nil?
          raise ArgumentError.new("--verify-deb-cache requires a boot profile")
        end
      
        navigate_boot_menu
        wait_for_shell
        verify_guest_agent
        configure_console
        verify_shared_directory
      
        Log.info { "GRML shared directory is operational" }
      
        if profile_name
          progress = ->(message : String) do
            STDOUT.print(message)
            STDOUT.flush
          end
          apply_profile(profile_name, verify_cache, progress)
        end
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
  
    module BuildISO
      module Private
        module DirectoryExistsInGuest
          private def directory_exists_in_guest?(path : String) : Bool
            result = @interaction.execute("test -d '#{path}'")
            result.success?
          end
        end
      
        module EnsureGrmlLiveCheckoutForBuild
          private def ensure_grml_live_checkout_for_build(ref : String, progress : Proc(String, Nil)?) : String
            command = <<-SHELL
              set -eu
              if [ ! -x '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live' ]; then
                echo "grml-live is not installed; run prepare_build_environment PROFILE_NAME first" >&2
                exit 10
              fi
              git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' fetch --force --depth=1 origin '#{ref}'
              git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' checkout --force --detach FETCH_HEAD
              git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' clean -fdx
              git -C '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}' rev-parse HEAD
              SHELL
          
            result = @interaction.execute_streaming(command, 10.minutes) do |_stream, chunk|
              report_build_environment_output(progress, chunk)
            end
            unless result.success?
              raise "Could not select grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
            result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
          end
        end
      
        module GrmlLiveBuildCommand
          private def grml_live_build_command(
            manifest : LiveBuildManifest,
            config_directory : String,
            output_directory : String,
            temporary_directory : String,
            install_directory : String
          ) : String
            args = [
              shell_quote("#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live"),
              "image-create",
              "-F",
              "-D", shell_quote(config_directory),
              "-s", shell_quote(manifest.suite),
              "-c", shell_quote(manifest.classes_argument),
              "--hostname", shell_quote(manifest.hostname),
              "--username", shell_quote(manifest.username),
              "--distri-name", shell_quote(manifest.distri_name),
              "--distri-info", shell_quote(manifest.distri_info),
              "-g", shell_quote(manifest.grml_name),
              "-r", shell_quote(manifest.release_name),
              "-v", shell_quote(manifest.version),
              "--bootstrap-mirror-url", shell_quote(manifest.bootstrap_mirror_url),
            ]
          
            unless manifest.boot_options.empty?
              args << "--boot-options" << shell_quote(manifest.boot_options.join(" "))
            end
            args << "--secure-boot" if manifest.secure_boot
            args << "-R" unless manifest.release
            if iso_name = manifest.iso_name
              args << "-i" << shell_quote(iso_name)
            end
            if build_date = manifest.date
              args << "-d" << shell_quote(build_date)
            end
            if wayback_date = manifest.wayback_date
              args << "-w" << shell_quote(wayback_date)
            end
            args << "-I" << shell_quote(install_directory) if directory_exists_in_guest?(install_directory)
            args << shell_quote(output_directory)
          
            environment = [
              "TMPDIR=#{shell_quote(temporary_directory)}",
              "APT_PROXY='http://127.0.0.1:3142'",
            ]
            if epoch = manifest.source_date_epoch
              environment << "SOURCE_DATE_EPOCH=#{epoch}"
            end
          
            "set -eu; runuser -u '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' -- env #{environment.join(" ")} #{args.join(" ")}"
          end
        end
      
        module MarkBuildRun
          private def mark_build_run(
            shared_run_directory : String,
            state : String,
            profile_name : String,
            run_id : String,
            checkout_commit : String,
            exit_code : Int32
          ) : Nil
            command = <<-SHELL
              set -eu
              printf 'run_id=%s\\nprofile=%s\\nstatus=%s\\ngrml_live_commit=%s\\nexit_code=%s\\n' \
                '#{run_id}' '#{profile_name}' '#{state}' '#{checkout_commit}' '#{exit_code}' > '#{shared_run_directory}/#{state}'
              rm -f '#{shared_run_directory}/BUILDING'
              SHELL
            result = @interaction.execute(command)
            unless result.success?
              raise "Could not write grml-live build status '#{state}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
          end
        end
      
        module PrepareBuildStage
          private def prepare_build_stage(
            profile_directory : String,
            stage_directory : String,
            config_directory : String,
            output_directory : String,
            temporary_directory : String,
            install_directory : String,
            shared_run_directory : String,
            shared_output_directory : String,
            progress : Proc(String, Nil)?
          ) : Nil
            profile_config = "#{profile_directory}/grml-live/config"
            profile_install = "#{profile_directory}/grml-live/chroot-install"
            command = <<-SHELL
              set -eu
              checkout='#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}'
              profile_config='#{profile_config}'
              profile_install='#{profile_install}'
              stage='#{stage_directory}'
              config='#{config_directory}'
              output='#{output_directory}'
              tmp='#{temporary_directory}'
              install='#{install_directory}'
              run='#{shared_run_directory}'
              shared_output='#{shared_output_directory}'
          
              mkdir -p '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_STAGE_ROOT}' "$stage" "$config" "$output" "$tmp" "$run" "$shared_output"
              chmod 0755 '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_STAGE_ROOT}' "$stage" "$config" "$output" "$tmp"
              cp -a "$checkout/config/." "$config/"
              if [ -d "$profile_config" ]; then
                cp -a "$profile_config/." "$config/"
              fi
              if [ -d "$profile_install" ]; then
                mkdir -p "$install"
                cp -a "$profile_install/." "$install/"
                find "$install" -type d -exec chmod 0755 {} +
                find "$install" -type f -exec chmod a+r {} +
              fi
          
              find "$config" -type d -exec chmod 0755 {} +
              find "$config" -type f -exec chmod a+r {} +
              chown -R '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' "$stage"
          
              cp '#{profile_directory}/grml-live/build.yml' "$run/build.yml"
              printf 'run_id=%s\\nprofile=%s\\nstatus=BUILDING\\n' \
                '#{File.basename(stage_directory)}' '#{File.basename(profile_directory)}' > "$run/BUILDING"
              SHELL
          
            result = @interaction.execute(command, 5.minutes)
            unless result.success?
              raise "Could not stage grml-live profile (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
            report_build_profile_progress(progress, "Merged upstream grml-live configuration with profile overrides")
          end
        end
      
        module PreserveBuildOutput
          private def preserve_build_output(
            output_directory : String,
            profile_directory : String,
            shared_run_directory : String,
            shared_output_directory : String
          ) : Nil
            command = <<-SHELL
              set -eu
              mkdir -p '#{shared_output_directory}'
              if [ -d '#{output_directory}' ]; then
                cp -R --preserve=mode,timestamps --no-preserve=ownership '#{output_directory}/.' '#{shared_output_directory}/'
              fi
              cp '#{profile_directory}/grml-live/build.yml' '#{shared_run_directory}/build.yml'
              SHELL
            result = @interaction.execute(command, 10.minutes)
            unless result.success?
              raise "Could not preserve grml-live build output (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
          end
        end
      
        module PreservePartialBuildOutput
          private def preserve_partial_build_output(
            output_directory : String,
            profile_directory : String,
            shared_run_directory : String,
            shared_output_directory : String,
            progress : Proc(String, Nil)?
          ) : Nil
            preserve_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory)
          rescue ex
            report_build_profile_progress(progress, "WARNING: could not preserve partial build output: #{ex.message}")
          end
        end
      
        module ReportBuildISOOutput
          private def report_build_iso_output(progress : Proc(String, Nil)?, chunk : String) : Nil
            return if chunk.empty?
            if callback = progress
              callback.call(chunk)
            else
              Log.info { chunk }
            end
          end
        end
      
        module VerifyBuildEnvironment
          private def verify_build_environment(manifest : LiveBuildManifest) : Nil
            workspace = ::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_WORKSPACE
            minimum_bytes = manifest.classes.includes?("GRML_FULL") ? 4_i64 * 1024 * 1024 * 1024 : 2_i64 * 1024 * 1024 * 1024
            command = <<-SHELL
              set -eu
              test -x '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_CHECKOUT}/grml-live'
              id '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' >/dev/null
              grep -q '^#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:' /etc/subuid
              grep -q '^#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}:' /etc/subgid
              for program in dpkg mksquashfs mmdebstrap xorriso runuser unshare newuidmap newgidmap findmnt mountpoint blkid; do
                command -v "$program" >/dev/null || {
                  echo "Required build program is missing: $program" >&2
                  exit 11
                }
              done
          
              mountpoint -q '#{workspace}' || {
                echo "Build workspace is not mounted: #{workspace}" >&2
                exit 12
              }
          
              filesystem=$(findmnt -n -o FSTYPE --target '#{workspace}')
              if [ "$filesystem" != ext4 ]; then
                echo "Build workspace must be ext4, found: $filesystem" >&2
                exit 13
              fi
          
              mount_target=$(findmnt -n -o TARGET --target '#{workspace}')
              if [ "$mount_target" != '#{workspace}' ]; then
                echo "Build workspace is not a dedicated mount point: $mount_target" >&2
                exit 14
              fi
          
              mount_options=$(findmnt -n -o OPTIONS --target '#{workspace}')
              for option in nodev noexec nosuid; do
                case ",$mount_options," in
                  *",$option,"*)
                    echo "Build workspace is mounted with $option; grml-live requires an executable, device-capable filesystem" >&2
                    exit 15
                    ;;
                esac
              done
          
              free_bytes=$(df -PB1 '#{workspace}' | awk 'NR == 2 {print $4}')
              if [ "$free_bytes" -lt #{minimum_bytes} ]; then
                echo "Insufficient free space in #{workspace}: $free_bytes bytes available, #{minimum_bytes} required" >&2
                exit 16
              fi
          
              runuser -u '#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
              SHELL
            result = @interaction.execute(command, 60.seconds)
            unless result.success?
              raise "grml-live build environment is not ready; run prepare_build_environment PROFILE_NAME (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
          end
        end
      
        module VerifyBuildISOOutput
          private def verify_build_iso_output(shared_output_directory : String) : Nil
            command = "find '#{shared_output_directory}/grml_isos' -maxdepth 1 -type f -name '*.iso' -print -quit | grep -q ."
            result = @interaction.execute(command)
            unless result.success?
              raise "grml-live returned success but no ISO file was found in #{shared_output_directory}/grml_isos"
            end
          end
        end
      
        include DirectoryExistsInGuest
        include EnsureGrmlLiveCheckoutForBuild
        include GrmlLiveBuildCommand
        include MarkBuildRun
        include PrepareBuildStage
        include PreserveBuildOutput
        include PreservePartialBuildOutput
        include ReportBuildISOOutput
        include VerifyBuildEnvironment
        include VerifyBuildISOOutput
      end
    
      module Public
        module BuildISO
          def build_iso(profile_name : String, progress : Proc(String, Nil)? = nil) : String
            validate_build_profile_name(profile_name)
            manifest = validate_profile(profile_name, progress)
            checkout_commit = ensure_grml_live_checkout_for_build(manifest.grml_live_ref, progress)
            verify_build_environment(manifest)
          
            timestamp = Time.utc.to_s("%Y%m%dT%H%M%SZ")
            nonce = Random.rand(0_i64..Int64::MAX).to_s(16)
            run_id = "#{timestamp}-#{nonce}"
            profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
            stage_directory = "#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_STAGE_ROOT}/#{run_id}"
            config_directory = "#{stage_directory}/config"
            output_directory = "#{stage_directory}/output"
            temporary_directory = "#{stage_directory}/tmp"
            install_directory = "#{stage_directory}/chroot-install"
            shared_run_directory = "#{::GRML::Agent::PrepareBuildEnvironment::GRML_LIVE_BUILD_RUN_ROOT}/#{profile_name}/#{run_id}"
            shared_output_directory = "#{shared_run_directory}/output"
          
            report_build_profile_progress(progress, "Starting grml-live image-create")
            report_build_profile_progress(progress, "Profile: #{profile_name}")
            report_build_profile_progress(progress, "grml-live commit: #{checkout_commit}")
            report_build_profile_progress(progress, "Run ID: #{run_id}")
            report_build_profile_progress(progress, "Artifacts: #{shared_run_directory}")
          
            failure_exit_code = -1
            begin
              prepare_build_stage(
                profile_directory,
                stage_directory,
                config_directory,
                output_directory,
                temporary_directory,
                install_directory,
                shared_run_directory,
                shared_output_directory,
                progress
              )
          
              command = grml_live_build_command(manifest, config_directory, output_directory, temporary_directory, install_directory)
              started_at = Time.instant
              result = @interaction.execute_streaming(command, 6.hours) do |_stream, chunk|
                report_build_iso_output(progress, chunk)
              end
              failure_exit_code = result.exit_code
          
              preserve_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory)
              elapsed = Time.instant - started_at
          
              unless result.success?
                raise "grml-live image-create failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
              end
          
              verify_build_iso_output(shared_output_directory)
              mark_build_run(shared_run_directory, "COMPLETE", profile_name, run_id, checkout_commit, result.exit_code)
              report_build_profile_progress(progress, "grml-live image-create completed in #{elapsed.total_seconds.round(1)}s")
              report_build_profile_progress(progress, "ISO files: #{shared_output_directory}/grml_isos")
              report_build_profile_progress(progress, "Build logs: #{shared_output_directory}/grml_logs")
              shared_output_directory
            rescue ex
              preserve_partial_build_output(output_directory, profile_directory, shared_run_directory, shared_output_directory, progress)
              begin
                run_exists = @interaction.execute("test -d '#{shared_run_directory}'")
                if run_exists.success?
                  building = @interaction.execute("test -s '#{shared_run_directory}/BUILDING'")
                  if building.success?
                    mark_build_run(shared_run_directory, "FAILED", profile_name, run_id, checkout_commit, failure_exit_code)
                  end
                end
              rescue marker_error
                report_build_profile_progress(progress, "WARNING: could not mark failed build: #{marker_error.message}")
              end
              raise ex
            ensure
              cleanup_result = @interaction.execute("rm -rf '#{stage_directory}'", 2.minutes)
              unless cleanup_result.success?
                report_build_profile_progress(progress, "WARNING: could not remove temporary build directory #{stage_directory}")
              end
            end
          end
        end
      
        include BuildISO
      end
    
      include Public
      include Private
    end
  
    module CopyExecutableToGuest
      def copy_executable_to_guest(source : String, destination : String) : Nil
        source_path = File.expand_path(source)
        raise "Host executable does not exist: #{source_path}" unless File.file?(source_path)
        unless destination.starts_with?("/") && destination != "/" && !destination.ends_with?("/")
          raise ArgumentError.new("Guest destination must be an absolute file path: #{destination.inspect}")
        end
        verify_shared_directory
        staged_path = nil.as(String?)
        begin
          staged_name = ".grml-agent-upload-#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}"
          staged_path = File.join(@vm.shared_path, staged_name)
          File.copy(source_path, staged_path)
          guest_path = File.join("/mnt/shared", staged_name)
          command = "install -D -m 0755 -- #{shell_quote(guest_path)} #{shell_quote(destination)}"
          result = @interaction.execute(command, 5.minutes)
          unless result.success?
            raise "Guest executable installation failed (exit=#{result.exit_code}): #{result.stderr}"
          end
        ensure
          if path = staged_path
            File.delete(path) if File.exists?(path)
          end
        end
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
            "printf 'run_id=%s\\n' '#{run.run_id}' > '#{bundle}/RUNNING'",
            progress
          )
        end
      
        report_bundle_stage(3, "Downloading and verifying alpine-chroot-install", progress) do
          run_bundle_command(
            "cd '#{tools}' && curl -fsSL " +
            "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/v0.14.0/alpine-chroot-install " +
            "-o alpine-chroot-install",
            progress
          )
          run_bundle_command(
            "cd '#{tools}' && printf '%s  %s\\n' " +
            "a181c3b3ebc2d7eb7e44d0178dd4ba78a2c9d3ae136f9192317e0bf9262fac3b alpine-chroot-install | sha256sum -c -",
            progress
          )
        end
      
        report_bundle_stage(4, "Downloading and verifying apk.static", progress) do
          run_bundle_command(
            "cd '#{tools}' && curl -fsSL " +
            "https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.7/x86_64/apk.static " +
            "-o apk.static",
            progress
          )
          run_bundle_command(
            "cd '#{tools}' && printf '%s  %s\\n' " +
            "bdd044e0fd6cc388c5e571e1093efa5f35f7767cc5aa338b0a2576a429009a62 apk.static | sha256sum -c -",
            progress
          )
          run_bundle_command("chmod +x '#{tools}/apk.static'", progress)
        end
      
        report_bundle_stage(5, "Extracting and installing Alpine signing keys", progress) do
          extract_alpine_keys(tools, keys, progress)
          run_bundle_command("mkdir -p '#{apk_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{apk_root}/etc/apk/keys/'", progress)
        end
      
        report_bundle_stage(6, "Fetching Alpine packages from main and community", progress) do
          fetch_alpine_packages(packages, apk_root, tools, mirror, branch, progress)
        end
      
        report_bundle_stage(7, "Verifying downloaded APK package signatures", progress) do
          run_bundle_command(run.package_verification_command, progress)
        end
      
        report_bundle_stage(8, "Building the local APK repository index for x86_64", progress) do
          run_bundle_command(run.repository_index_command, progress)
        end
      
        report_bundle_stage(9, "Checking the local APK repository", progress) do
          inspect_local_repository(bundle, repository, packages, progress)
        end
      
        report_bundle_stage(10, "Verifying offline installation", progress) do
          verify_offline_repository(repository, bundle, tools, keys, arch, progress)
        end
      
        report_bundle_stage(11, "Writing bundle manifest and SHA-256 checksums", progress) do
          run_bundle_command(run.write_manifest_command(branch), progress)
        end
      
        report_bundle_stage(12, "Verifying bundle manifest and every checksum", progress) do
          run_bundle_command(run.verify_manifest_command(branch), progress)
        end
      
        report_bundle_stage(13, "Marking the verified run COMPLETE", progress) do
          run_bundle_command(run.complete_marker_command, progress)
        end
      
        report_bundle_stage(14, "Publishing the LATEST bundle pointer", progress) do
          run_bundle_command(run.publish_latest_command, progress)
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
          callback.call("#{message}\n")
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
      
      private def extract_alpine_keys(tools : String, keys : String, progress : Proc(String, Nil)?) : Nil
        script = "#{tools}/alpine-chroot-install"
        command = "awk '/^ALPINE_KEYS=/,/^\\x27$/ { if (NR > 1 && $0 !~ /^ALPINE_KEYS=/ && $0 !~ /^\\x27$/) print }' '#{script}' | " +
          "while IFS= read -r line; do " +
          "id=\${line%%:*}; content=\${line#*:}; " +
          "[ -n \"\${id}\" ] || continue; " +
          "file='#{keys}/alpine-devel@lists.alpinelinux.org-'\${id}'.rsa.pub'; " +
          "printf '%s\\n' '-----BEGIN PUBLIC KEY-----' > \"\${file}\"; " +
          "printf '%b\\n' \"\${content}\" >> \"\${file}\"; " +
          "printf '%s\\n' '-----END PUBLIC KEY-----' >> \"\${file}\"; done"
        run_bundle_command(command, progress)
      end
      
      private def fetch_alpine_packages(
        packages : String,
        apk_root : String,
        tools : String,
        mirror : String,
        branch : String,
        progress : Proc(String, Nil)?
      ) : Nil
        command = "'#{tools}/apk.static' --root '#{apk_root}' --keys-dir '#{apk_root}/etc/apk/keys' --no-cache --arch x86_64 " +
          "--repository #{mirror}/#{branch}/main " +
          "--repository #{mirror}/#{branch}/community " +
          "fetch --recursive --output '#{packages}' alpine-base alpine-keys"
        run_bundle_command(command, progress)
      end
      
      private def inspect_local_repository(
        bundle : String,
        repository : String,
        packages : String,
        progress : Proc(String, Nil)?
      ) : Nil
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
      
        result = @interaction.execute_streaming(command, 300.seconds) do |_stream, chunk|
          report_bundle_output(progress, chunk)
        end
        unless result.success?
          raise "Local APK repository preflight failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
        end
      end
      
      private def verify_offline_repository(
        repository : String,
        bundle : String,
        tools : String,
        keys : String,
        arch : String,
        progress : Proc(String, Nil)?
      ) : Nil
        test_root = "#{bundle}/verify-root"
        run_bundle_command(
          "rm -rf '#{test_root}' && mkdir -p '#{test_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{test_root}/etc/apk/keys/'",
          progress
        )
        command = "'#{tools}/apk.static' --root '#{test_root}' --keys-dir '#{test_root}/etc/apk/keys' " +
          "--allow-untrusted --no-network --arch #{arch} --repository '#{repository}' " +
          "add --initdb alpine-base alpine-keys && " +
          "test -s '#{test_root}/lib/apk/db/installed' && " +
          "grep -Fqx 'P:alpine-base' '#{test_root}/lib/apk/db/installed' && " +
          "grep -Fqx 'P:alpine-keys' '#{test_root}/lib/apk/db/installed'"
        run_bundle_command(command, progress)
        run_bundle_command("rm -rf '#{test_root}'", progress)
      end
      
      private def run_bundle_command(command : String, progress : Proc(String, Nil)? = nil) : Nil
        result = @interaction.execute_streaming(command, 300.seconds) do |_stream, chunk|
          report_bundle_output(progress, chunk)
        end
        unless result.success?
          raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\n#{result.stderr}\n#{result.stdout}"
        end
      end
      
      private def report_bundle_output(progress : Proc(String, Nil)?, chunk : String) : Nil
        return if chunk.empty?
      
        if callback = progress
          callback.call(chunk)
        else
          Log.info { chunk }
        end
      end
    end
  
    module PrepareBuildEnvironment
      module Private
        module BuildBuilderAccountCommand
          private def build_builder_account_command : String
            <<-SHELL
              set -eu
              echo "[account] Ensuring #{GRML_LIVE_BUILDER} exists"
              id '#{GRML_LIVE_BUILDER}' >/dev/null 2>&1 ||
                useradd --create-home --user-group --shell /bin/bash '#{GRML_LIVE_BUILDER}'
              echo "[account] Ensuring subordinate UID/GID ranges"
              #{build_subordinate_id_command}
              echo "[account] Testing user namespace mappings"
              runuser -u '#{GRML_LIVE_BUILDER}' -- unshare --user --map-auto --map-user=65536 --map-group=65536 --pid --mount-proc --uts --fork --kill-child --setuid 0 --setgid 0 true
              echo "[account] User namespace mappings are usable"
            SHELL
          end
        end
      
        module BuildDependenciesCommand
          private def build_dependencies_command(packages : Array(String)) : String
            <<-SHELL
              set -eu
              echo "[apt] Updating package indexes"
              apt-get update
              echo "[apt] Installing #{packages.size} packages"
              DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends #{packages.join(" ")}
              echo "[apt] Build dependencies are installed"
            SHELL
          end
        end
      
        module BuildEnvironmentCommandError
          private def build_environment_command_error(label, exit_code, stdout, stderr) : String
            details = ["stderr:\n#{stderr}", "stdout:\n#{stdout}"].reject { |item| item.ends_with?(":\n") }
            details = ["No output was captured; inspect the persistent diagnostic log."] if details.empty?
            base = "/var/log/grml-agent/build-environment/#{label}"
            "Build environment command '#{label}' failed (exit=#{exit_code}):\n#{details.join("\n")}\nScript: #{base}.sh\nLog: #{base}.log"
          end
        end
      
        module BuildEnvironmentDiagnosticCommand
          private def build_environment_diagnostic_command(command : String, label : String) : String
            unless label.matches?(/\A[a-z0-9][a-z0-9-]*\z/)
              raise ArgumentError.new("Invalid build diagnostic label: #{label.inspect}")
            end
            script = build_environment_diagnostic_script(command)
            directory = "/var/log/grml-agent/build-environment"
            wrapper = [
              "set -eu", "mkdir -p #{directory}",
              "log_path=#{directory}/#{label}.log",
              "script_path=#{directory}/#{label}.sh",
              ": > \"$log_path\"",
              "printf '%s\\n' #{shell_quote(script)} > \"$script_path\"",
              "exec > >(tee -a \"$log_path\") 2> >(tee -a \"$log_path\" >&2)",
              "printf '[diagnostics] script: %s\\n[diagnostics] log: %s\\n' \"$script_path\" \"$log_path\"",
              "bash \"$script_path\"",
            ].join("\n")
            "/bin/bash -c #{shell_quote(wrapper)}"
          end
        end
      
        module BuildEnvironmentDiagnosticScript
          private def build_environment_diagnostic_script(command : String) : String
            [
              "set -Eeuo pipefail",
              "trap 'status=$?; printf \"[command failed] exit=%s line=%s command=%s\\n\" \"$status\" \"$LINENO\" \"$BASH_COMMAND\" >&2' ERR",
              "set -x",
              command,
            ].join("\n")
          end
        end
      
        module BuildSubordinateIDCommand
          private def build_subordinate_id_command : String
            "python3 -c #{shell_quote(build_subordinate_id_script)}"
          end
        end
      
        module BuildSubordinateIDScript
          private def build_subordinate_id_script : String
            [
              "from pathlib import Path",
              "username, count = \"#{GRML_LIVE_BUILDER}\", 65536",
              "def ensure_range(filename):",
              "    path = Path(filename)",
              "    path.touch(exist_ok=True)",
              "    entries = []",
              "    for line in path.read_text(encoding=\"utf-8\").splitlines():",
              "        fields = line.split(\":\")",
              "        if len(fields) == 3:",
              "            try:",
              "                entries.append((fields[0], int(fields[1]), int(fields[2])))",
              "            except ValueError:",
              "                continue",
              "    if any(name == username and size >= count for name, _, size in entries): return",
              "    start = 100000",
              "    while True:",
              "        ends = [first + size for _, first, size in entries if start < first + size and start + count > first]",
              "        if not ends: break",
              "        start = max(ends)",
              "    with path.open(\"a\", encoding=\"utf-8\") as stream:",
              "        stream.write(f\"{username}:{start}:{count}\\n\")",
              "ensure_range(\"/etc/subuid\")",
              "ensure_range(\"/etc/subgid\")",
            ].join("\n")
          end
        end
      
        module CheckoutGrmlLive
          private def checkout_grml_live(ref : String, progress : Proc(String, Nil)? = nil) : String
            report_build_environment_stage(6, "Checking out grml-live source", progress) do
              checkout_grml_live_ref(ref, progress)
            end
          end
        end
      
        module CheckoutGrmlLiveCommand
          private def checkout_grml_live_command(ref : String) : String
            <<-SHELL
              set -eu
              if [ ! -d '#{GRML_LIVE_CHECKOUT}/.git' ]; then
                echo "[git] Cloning grml-live repository"
                rm -rf '#{GRML_LIVE_CHECKOUT}'
                git clone --filter=blob:none --no-checkout https://github.com/grml/grml-live.git '#{GRML_LIVE_CHECKOUT}'
              fi
              echo "[git] Fetching ref: #{ref}"
              git -C '#{GRML_LIVE_CHECKOUT}' fetch --progress --force --depth=1 origin '#{ref}'
              echo "[git] Checking out fetched commit"
              git -C '#{GRML_LIVE_CHECKOUT}' checkout --force --detach FETCH_HEAD
              git -C '#{GRML_LIVE_CHECKOUT}' clean -fdx
              git -C '#{GRML_LIVE_CHECKOUT}' rev-parse HEAD
            SHELL
          end
        end
      
        module CheckoutGrmlLiveRef
          private def checkout_grml_live_ref(ref : String, progress : Proc(String, Nil)?) : String
            unless ref.matches?(/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/) && !ref.split('/').includes?("..")
              raise ArgumentError.new("Invalid grml-live git ref: #{ref.inspect}")
            end
            result = @interaction.execute_streaming(checkout_grml_live_command(ref), 10.minutes) do |_stream, chunk|
              report_build_environment_output(progress, chunk)
            end
            unless result.success?
              raise "Could not check out grml-live ref '#{ref}' (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
            end
            result.stdout.lines.last?.try(&.strip) || raise "Could not determine grml-live checkout commit"
          end
        end
      
        module EnsureBuildWorkspace
          private def ensure_build_workspace(progress : Proc(String, Nil)?) : Nil
            report_build_environment_stage(5, "Provisioning persistent ext4 build workspace", progress) do
              disk = ensure_ext4_disk(
                GRML_LIVE_BUILD_DISK_NAME, GRML_LIVE_BUILD_DISK_SIZE,
                GRML_LIVE_BUILD_WORKSPACE, "qcow2", progress
              )
              report_build_profile_progress(progress, "Persistent build workspace: #{disk}")
            end
          end
        end
      
        module PrepareBuildBuilderAccount
          private def prepare_build_builder_account(progress : Proc(String, Nil)?) : Nil
            report_build_environment_stage(4, "Preparing unprivileged builder account and UID/GID mappings", progress) do
              run_build_environment_command(build_builder_account_command, 60.seconds, progress, "builder-account")
            end
          end
        end
      
        module PrepareBuildCache
          private def prepare_build_cache(progress) : Nil
            report_build_environment_stage(2, "Preparing shared Debian package cache", progress) do
              prepare_deb_cache(progress)
            end
          end
        end
      
        module PrepareBuildDependencies
          private def prepare_build_dependencies(packages : Array(String), progress) : Nil
            all_packages = (GRML_LIVE_BUILDER_PACKAGES + packages).uniq
            report_build_environment_stage(3, "Installing grml-live build dependencies", progress) do
              report_build_profile_progress(progress, "Builder packages: #{all_packages.size}")
              run_build_environment_command(build_dependencies_command(all_packages), 45.minutes, progress, "dependencies")
            end
          end
        end
      
        module PrepareBuildProfile
          private def prepare_build_profile(profile_name, progress)
            report_build_environment_stage(1, "Validating build profile", progress) do
              directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
              verify_profile_tree(directory)
              packages = read_builder_packages(directory)
              manifest = validate_profile(profile_name, progress)
              {manifest: manifest, packages: packages}
            end
          end
        end
      
        module ReportBuildEnvironmentOutput
          private def report_build_environment_output(progress : Proc(String, Nil)?, chunk : String) : Nil
            return if chunk.empty?
            if callback = progress
              callback.call(chunk)
            else
              Log.info { chunk }
            end
          end
        end
      
        module ReportBuildEnvironmentStage
          private def report_build_environment_stage(
            index : Int32, title : String, progress : Proc(String, Nil)?, &block : -> T
          ) : T forall T
            label = "[#{index}/6] #{title}"
            started_at = Time.instant
            report_build_profile_progress(progress, "#{label} ...")
            begin
              result = yield
            rescue ex
              elapsed = Time.instant - started_at
              report_build_profile_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
              raise "Failed during #{title}: #{ex.message}"
            end
            elapsed = Time.instant - started_at
            report_build_profile_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
            result
          end
        end
      
        module RunBuildEnvironmentCommand
          private def run_build_environment_command(command, timeout, progress, label = "command") : Nil
            stdout, stderr = IO::Memory.new, IO::Memory.new
            wrapped = build_environment_diagnostic_command(command, label)
            result = @interaction.execute_streaming(wrapped, timeout) do |stream, chunk|
              (stream == :stderr ? stderr : stdout).write(chunk.to_slice)
              report_build_environment_output(progress, chunk)
            end
            return if result.success?
            stdout_text = stdout.to_s.empty? ? result.stdout : stdout.to_s
            stderr_text = stderr.to_s.empty? ? result.stderr : stderr.to_s
            raise build_environment_command_error(label, result.exit_code, stdout_text, stderr_text)
          end
        end
      
        include CheckoutGrmlLive
        include CheckoutGrmlLiveRef
        include CheckoutGrmlLiveCommand
        include EnsureBuildWorkspace
        include ReportBuildEnvironmentOutput
        include ReportBuildEnvironmentStage
        include RunBuildEnvironmentCommand
        include BuildEnvironmentDiagnosticCommand
        include BuildEnvironmentDiagnosticScript
        include BuildEnvironmentCommandError
        include PrepareBuildProfile
        include PrepareBuildCache
        include PrepareBuildDependencies
        include BuildDependenciesCommand
        include PrepareBuildBuilderAccount
        include BuildBuilderAccountCommand
        include BuildSubordinateIDCommand
        include BuildSubordinateIDScript
      end
    
      module Public
        module PrepareBuildEnvironment
          def prepare_build_environment(profile_name : String, progress : Proc(String, Nil)? = nil) : Nil
            validate_build_profile_name(profile_name)
            report_build_profile_progress(progress, "Preparing grml-live build environment for '#{profile_name}'")
            profile = prepare_build_profile(profile_name, progress)
            prepare_build_cache(progress)
            prepare_build_dependencies(profile[:packages], progress)
            prepare_build_builder_account(progress)
            ensure_build_workspace(progress)
            checkout_grml_live(profile[:manifest].grml_live_ref, progress)
            report_build_profile_progress(progress, "grml-live build environment is ready")
          end
        end
      
        include PrepareBuildEnvironment
      end
    
      GRML_LIVE_CHECKOUT = "/opt/grml-live"
      GRML_LIVE_BUILDER = "grml-live-builder"
      GRML_LIVE_BUILD_DISK_NAME = "grml-live-build"
      GRML_LIVE_BUILD_DISK_SIZE = "32G"
      GRML_LIVE_BUILD_WORKSPACE = "/mnt/grml-live-build"
      GRML_LIVE_BUILD_STAGE_ROOT = GRML_LIVE_BUILD_WORKSPACE + "/stage"
      GRML_LIVE_BUILD_RUN_ROOT = "/mnt/shared/grml-live/runs"
      GRML_LIVE_BUILDER_PACKAGES = %w(
        ca-certificates curl dosfstools e2fsprogs git jo mmdebstrap moreutils mtools
        python3 python3-yaml rsync socat squashfs-tools uidmap util-linux xorriso
      )
      
      include Public
      include Private
    end
  
    module PrepareDebCache
      DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
      DEB_CACHE_PROXY_URL = "http://127.0.0.1:3142"
      
      def prepare_deb_cache(progress : Proc(String, Nil)? = nil) : Nil
        started_at = Time.instant
        report_deb_cache_progress(progress, "Preparing shared Debian package cache")
      
        report_deb_cache_stage(1, "Checking the shared directory", progress) do
          command = <<-BASH
            set -eu
            if ! mountpoint -q /mnt/shared; then
              echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
              exit 20
            fi
            probe=$(mktemp /mnt/shared/.grml-agent-deb-cache.XXXXXX)
            rm -f "$probe"
            df -h /mnt/shared | tail -n 1
          BASH
          run_deb_cache_command(command)
        end
      
        report_deb_cache_stage(2, "Checking or installing apt-cacher-ng", progress) do
          command = <<-BASH
            set -eu
            if dpkg-query -W -f='${Status}\n' apt-cacher-ng 2>/dev/null | grep -qx 'install ok installed'; then
              echo "apt-cacher-ng is already installed"
            else
              echo "Installing apt-cacher-ng; this first installation requires network access"
              export DEBIAN_FRONTEND=noninteractive
              apt-get -o Acquire::http::Proxy=DIRECT update
              apt-get -o Acquire::http::Proxy=DIRECT install -y --no-install-recommends apt-cacher-ng
              echo "apt-cacher-ng installation completed"
            fi
          BASH
          run_deb_cache_command(command, 5.minutes, progress)
        end
      
        report_deb_cache_stage(3, "Preparing persistent cache storage", progress) do
          command = <<-BASH
            set -eu
            cache_path='#{DEB_CACHE_DIRECTORY}/proxy'
            service_dropin="/etc/systemd/system/apt-cacher-ng.service.d/grml-shared-cache.conf"
      
            mkdir -p "$cache_path"
            install -d -o apt-cacher-ng -g apt-cacher-ng -m 0755 "$cache_path"
      
            # Load after Debian's zz_debconf.conf so this CacheDir takes precedence.
            rm -f /etc/apt-cacher-ng/90-grml-agent.conf
            printf '%s\\n' \\
              'CacheDir: /mnt/shared/deb-cache/proxy' \\
              'BindAddress: 127.0.0.1' \\
              'ReportPage: acng-report.html' \\
              > /etc/apt-cacher-ng/zzzz-grml-agent.conf
      
            # Debian's service restricts writable paths. Permit the persistent
            # shared cache and prevent startup before the 9p mount exists.
            mkdir -p "$(dirname "$service_dropin")"
            printf '%s\\n' \\
              '[Unit]' \\
              'ConditionPathIsMountPoint=/mnt/shared' \\
              '' \\
              '[Service]' \\
              'ReadWritePaths=/mnt/shared/deb-cache/proxy' \\
              > "$service_dropin"
      
            if ! runuser -u apt-cacher-ng -- test -w "$cache_path"; then
              echo "apt-cacher-ng cannot write to shared cache directory: $cache_path" >&2
              exit 22
            fi
      
            printf 'Cache directory: %s\n' "$cache_path"
            echo "apt-cacher-ng service-user write access: OK"
          BASH
          run_deb_cache_command(command)
        end
      
        report_deb_cache_stage(4, "Configuring APT and grml-live", progress) do
          command = <<-BASH
            set -eu
            proxy_url='#{DEB_CACHE_PROXY_URL}'
      
            printf '%s\\n' 'Acquire::http::Proxy "http://127.0.0.1:3142";' \\
              > /etc/apt/apt.conf.d/90-grml-agent-deb-cache
      
            mkdir -p /etc/profile.d
            printf '%s\\n' 'export APT_PROXY="http://127.0.0.1:3142"' \\
              > /etc/profile.d/90-grml-agent-deb-cache.sh
            chmod 0644 /etc/apt/apt.conf.d/90-grml-agent-deb-cache /etc/profile.d/90-grml-agent-deb-cache.sh
      
            if [ -f /etc/environment ]; then
              sed -i '/^APT_PROXY=/d' /etc/environment
            fi
            printf 'APT_PROXY=%s\n' "$proxy_url" >> /etc/environment
      
            printf 'APT HTTP proxy: %s\nAPT_PROXY: %s\n' "$proxy_url" "$proxy_url"
          BASH
          run_deb_cache_command(command)
        end
      
        report_deb_cache_stage(5, "Starting apt-cacher-ng", progress) do
          command = <<-BASH
            set -eu
            # A forced VM shutdown during verify_deb_cache can leave its temporary
            # offline-mode override behind. Always restore normal upstream access
            # when preparing the cache after a boot.
            rm -f '/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf'
            systemctl daemon-reload
      
            diagnose_start_failure() {
              systemctl --no-pager --full status apt-cacher-ng.service >&2 || true
              journalctl -u apt-cacher-ng.service -b -n 80 --no-pager >&2 || true
      
              for log_file in /var/log/apt-cacher-ng/*.err; do
                if [ -f "$log_file" ]; then
                  echo "----- $log_file -----" >&2
                  tail -n 80 "$log_file" >&2 || true
                fi
              done
            }
      
            if ! systemctl restart apt-cacher-ng.service; then
              diagnose_start_failure
              echo "apt-cacher-ng could not be restarted" >&2
              exit 24
            fi
      
            if ! systemctl is-active --quiet apt-cacher-ng.service; then
              diagnose_start_failure
              echo "apt-cacher-ng did not remain active after restart" >&2
              exit 25
            fi
      
            systemctl is-active apt-cacher-ng.service
          BASH
          run_deb_cache_command(command, 45.seconds)
        end
      
        report_deb_cache_stage(6, "Checking proxy readiness", progress) do
          command = <<-BASH
            set -eu
            ready=0
            for attempt in $(seq 1 15); do
              if systemctl is-active --quiet apt-cacher-ng &&
                 curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
                ready=1
                break
              fi
              sleep 1
            done
      
            if [ "$ready" -ne 1 ]; then
              systemctl --no-pager --full status apt-cacher-ng >&2 || true
              journalctl -u apt-cacher-ng -n 40 --no-pager >&2 || true
              echo "apt-cacher-ng did not become ready on 127.0.0.1:3142" >&2
              exit 21
            fi
      
            echo "Service: active"
            echo "Report endpoint: http://127.0.0.1:3142/acng-report.html (HTTP OK)"
          BASH
          run_deb_cache_command(command, 30.seconds)
        end
      
        report_deb_cache_stage(7, "Reporting cache status", progress) do
          command = <<-BASH
            set -eu
            cache_path='#{DEB_CACHE_DIRECTORY}/proxy'
            package_count=$(find "$cache_path" -type f -name '*.deb' | wc -l | tr -d '[:space:]')
            cache_size=$(du -sh "$cache_path" | cut -f1)
            free_bytes=$(df -PB1 /mnt/shared | awk 'NR == 2 {print $4}')
            proxy_setting=$(apt-config dump | awk -F '"' '/Acquire::http::Proxy / {print $2; exit}')
            environment_proxy=$(sed -n 's/^APT_PROXY=//p' /etc/environment | tail -n 1)
      
            printf 'Cache directory: %s\nCached .deb archives: %s\nCache size: %s\nShared filesystem free: %s bytes\nService: %s\nAPT HTTP proxy: %s\nAPT_PROXY in /etc/environment: %s\nPackage cache verification: not run (use verify_deb_cache [package])\n' \
              "$cache_path" "$package_count" "$cache_size" "$free_bytes" \
              "$(systemctl is-active apt-cacher-ng)" "$proxy_setting" "$environment_proxy"
          BASH
          run_deb_cache_command(command)
        end
      
        elapsed = Time.instant - started_at
        report_deb_cache_progress(progress, "Shared Debian package cache is ready")
        report_deb_cache_progress(progress, "Package reuse is not yet verified; run verify_deb_cache [package]")
        report_deb_cache_progress(progress, "Total preparation time: #{elapsed.total_seconds.round(1)}s")
      end
      
      private def report_deb_cache_stage(
        index : Int32,
        title : String,
        progress : Proc(String, Nil)?,
        &block : -> String
      ) : Nil
        label = "[#{index}/7] #{title}"
        started_at = Time.instant
        report_deb_cache_progress(progress, "#{label} ...")
      
        begin
          details = yield
        rescue ex
          elapsed = Time.instant - started_at
          report_deb_cache_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
          raise "Failed during #{title}: #{ex.message}"
        end
      
        elapsed = Time.instant - started_at
        report_deb_cache_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
        report_deb_cache_progress(progress, details) unless details.empty?
      end
      
      private def run_deb_cache_command(
        command : String,
        timeout : Time::Span = 30.seconds,
        progress : Proc(String, Nil)? = nil
      ) : String
        result = @interaction.execute_streaming(command, timeout) do |_stream, chunk|
          report_deb_cache_output(progress, chunk)
        end
        unless result.success?
          raise "Guest command failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
        end
      
        ""
      end
      
      private def report_deb_cache_output(progress : Proc(String, Nil)?, chunk : String) : Nil
        return if chunk.empty?
      
        if callback = progress
          callback.call(chunk)
        else
          Log.info { chunk }
        end
      end
      
      private def report_deb_cache_progress(progress : Proc(String, Nil)?, message : String) : Nil
        if callback = progress
          callback.call("#{message}\n")
        else
          Log.info { message }
        end
      end
    end
  
    module Storage
      module Private
        module AttachDiskWithSerial
          private def attach_disk_with_serial(
            path : String,
            format : String,
            suffix : String? = nil,
            serial : String? = nil
          ) : NamedTuple(device_id: String, serial: String)
            validate_disk_format(format)
            expanded_path = File.expand_path(path)
            raise "Disk image does not exist: #{expanded_path}" unless File.file?(expanded_path)
          
            identifier = suffix || Random.rand(1..Int32::MAX).to_s
            unless identifier.matches?(/\A[A-Za-z0-9_-]+\z/)
              raise ArgumentError.new("Invalid QEMU disk identifier: #{identifier.inspect}")
            end
            device_serial = serial || "grml-#{identifier}"
            unless device_serial.matches?(/\A[A-Za-z0-9._-]{1,20}\z/)
              raise ArgumentError.new("Invalid QEMU disk serial: #{device_serial.inspect}")
            end
          
            file_node = "grml_disk_file_#{identifier}"
            disk_node = "grml_disk_#{identifier}"
            device_id = "grml_virtio_disk_#{identifier}"
          
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
                "serial" => device_serial
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
          
            {device_id: device_id, serial: device_serial}
          end
        end
      
        module CaptureStorageCommand
          private def capture_storage_command(command : String, arguments : Array(String)) : JSON::Any
            output, error = IO::Memory.new, IO::Memory.new
            result = Process.run(command, arguments, output: output, error: error)
            JSON.parse({"argv" => [command] + arguments, "exit_code" => result.exit_code, "stdout" => output.to_s, "stderr" => error.to_s}.to_json)
          rescue ex
            JSON.parse({"argv" => [command] + arguments, "error" => ex.message}.to_json)
          end
        end
      
        module CaptureStorageQMP
          private def capture_storage_qmp(command : String) : JSON::Any
            @vm.execute_qmp(command)
          rescue ex
            JSON.parse({"error" => ex.message}.to_json)
          end
        end
      
        module CreateDiskImage
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
        end
      
        module CreateExt4Partition
          private def create_ext4_partition : String
            <<-SCRIPT
              if [ ! -b "$partition" ]; then
                partition_table=$(blkid -p -o value -s PTTYPE "$disk" 2>/dev/null || true)
                if [ -n "$partition_table" ]; then
                  echo "Waiting for existing guest partition device"
                  for attempt in $(seq 1 50); do
                    [ -b "$partition" ] && break
                    sleep 0.1
                  done
                fi
                if [ ! -b "$partition" ]; then
                  filesystem=$(blkid -p -o value -s TYPE "$disk" 2>/dev/null || true)
                  if [ -n "$partition_table" ] || [ -n "$filesystem" ]; then
                    echo "Disk has unexpected signatures; refusing to repartition" >&2
                    exit 1
                  fi
                  echo "Creating GPT partition table and ext4 partition"
                  printf 'label: gpt\\n, , L\\n' | sfdisk "$disk"
                  blockdev --rereadpt "$disk"
                  udevadm settle
                  for attempt in $(seq 1 50); do
                    [ -b "$partition" ] && break
                    sleep 0.1
                  done
                fi
              fi
              [ -b "$partition" ] || { echo "Partition did not appear: $partition" >&2; exit 1; }
            SCRIPT
          end
        end
      
        module DiskImageVirtualSize
          private def disk_image_virtual_size(json : String) : Int64
            JSON.parse(json).as_h["virtual-size"].as_i64
          rescue ex
            raise "Invalid disk image virtual-size JSON: #{ex.message}"
          end
        end
      
        module DiskSizeMultiplier
          private def disk_size_multiplier(unit : String?) : Int64
            case unit
            when "K" then 1024_i64
            when "M" then 1_048_576_i64
            when "G" then 1_073_741_824_i64
            when "T" then 1_099_511_627_776_i64
            when "P" then 1_125_899_906_842_624_i64
            else        1_i64
            end
          end
        end
      
        module EnsureExt4Disk
          private def ensure_ext4_disk(
            name : String, size : String, mountpoint : String,
            format : String = "qcow2", progress : Proc(String, Nil)? = nil
          ) : String
            guest_mountpoint = validate_guest_mountpoint(mountpoint)
            path = prepare_ext4_disk_image(name, size, format, progress)
            ensure_ext4_disk_attachment(path, name, format, progress)
            provision_ext4_disk(name, guest_mountpoint, path, progress)
            "#{path} (ext4 mounted at #{guest_mountpoint})"
          end
        end
      
        module EnsureExt4DiskAttachment
          private def ensure_ext4_disk_attachment(path, name, format, progress) : Nil
            suffix = name == "grml-live-build" ? "live_build" : name.gsub(/[^A-Za-z0-9_-]/, "_")
            device_id = "grml_virtio_disk_#{suffix}"
            if find_attached_disk_info_by_path(path)
              report_storage_progress(progress, "Reusing QEMU disk attachment for image: #{path}")
            else
              report_storage_progress(progress, "Attaching disk to QEMU: #{device_id}")
              attach_disk_with_serial(path, format, suffix, name)
            end
          end
        end
      
        module EnsureExt4ProvisioningCommand
          private def ensure_ext4_provisioning_command(serial : String, mountpoint : String) : String
            [
              "set -eu",
              "serial=#{shell_quote(serial)}",
              "disk=#{shell_quote("/dev/disk/by-id/virtio-#{serial}")}",
              "partition=\"\"",
              "mountpoint=#{shell_quote(mountpoint)}",
              report_missing_ext4_disk,
              wait_for_ext4_disk,
              verify_ext4_mount,
              create_ext4_partition,
              format_ext4_partition,
              mount_ext4_partition,
            ].join("\n")
          end
        end
      
        module ExecuteQMPChecked
          private def execute_qmp_checked(command : String, arguments : Hash(String, JSON::Any)) : JSON::Any
            response = @vm.execute_qmp(command, arguments)
            if error = response.as_h["error"]?
              raise "QMP #{command} failed: #{error}"
            end
            response
          end
        end
      
        module ExpectedDiskImageSize
          private def expected_disk_image_size(requested_size : String) : Int64
            match = /\A([1-9][0-9]*)([KMGTP])?\z/i.match(requested_size)
            raise ArgumentError.new("Invalid disk size: #{requested_size.inspect}") unless match
            match[1].to_i64 * disk_size_multiplier(match[2]?.try(&.upcase))
          end
        end
      
        module Ext4ProvisioningCommand
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
        end
      
        module FindAttachedDiskInfo
          private def find_attached_disk_info(device_id : String) : JSON::Any?
            response = execute_qmp_checked("query-block", Hash(String, JSON::Any).new)
            records = response.as_h["return"]?.try(&.as_a)
            raise "QMP query-block returned no block-device list" unless records
            record = records.find do |item|
              block = item.as_h
              block["qdev"]?.try(&.as_s) == device_id || block["device"]?.try(&.as_s) == device_id
            end
            return unless record
            inserted = record.as_h["inserted"]?
            raise "QMP reports #{device_id} attached without backing-file details" unless inserted
            inserted
          end
        end
      
        module FindAttachedDiskInfoByPath
          private def find_attached_disk_info_by_path(path : String) : JSON::Any?
            response = execute_qmp_checked("query-block", Hash(String, JSON::Any).new)
            records = response.as_h["return"]?.try(&.as_a)
            raise "QMP query-block returned no block-device list" unless records
            matches = records.compact_map do |item|
              inserted = item.as_h["inserted"]?
              attached_path = inserted.try { |block| block.as_h["file"]?.try(&.as_s) }
              inserted if attached_path && File.expand_path(attached_path) == File.expand_path(path)
            end
            raise "QEMU reports multiple devices for image: #{path}" if matches.size > 1
            matches.first?
          end
        end
      
        module FindAttachedDiskPath
          private def find_attached_disk_path(device_id : String) : String?
            inserted = find_attached_disk_info(device_id)
            return unless inserted
            path = inserted.as_h["file"]?.try(&.as_s)
            raise "QMP reports #{device_id} attached without a backing-file path" unless path
            path
          end
        end
      
        module FormatExt4Partition
          private def format_ext4_partition : String
            <<-SCRIPT
              filesystem=$(blkid -p -o value -s TYPE "$partition" 2>/dev/null || true)
              if [ -z "$filesystem" ]; then
                echo "Formatting new partition as ext4 (mkfs.ext4)"
                mkfs.ext4 -F "$partition"
              elif [ "$filesystem" != ext4 ]; then
                echo "Existing partition has filesystem '$filesystem'; refusing to format it" >&2
                exit 1
              else
                echo "Reusing existing ext4 filesystem"
              fi
            SCRIPT
          end
        end
      
        module MountExt4Partition
          private def mount_ext4_partition : String
            <<-SCRIPT
              echo "Mounting ext4 workspace at $mountpoint"
              mkdir -p "$mountpoint"
              mount -t ext4 "$partition" "$mountpoint"
              echo "Verifying mounted filesystem"
              findmnt -rn -t ext4 --target "$mountpoint" >/dev/null
              printf 'Mounted %s on %s as ext4\\n' "$partition" "$mountpoint"
            SCRIPT
          end
        end
      
        module PrepareExt4DiskImage
          private def prepare_ext4_disk_image(name, size, format, progress) : String
            validate_disk_name(name)
            raise ArgumentError.new("Invalid disk size: #{size.inspect}") unless size.matches?(DISK_SIZE_PATTERN)
            validate_disk_format(format)
            path = File.join(File.expand_path("./disks"), "#{name}.#{format}")
            if File.exists?(path)
              raise "Disk image path is not a regular file: #{path}" unless File.file?(path)
              report_storage_progress(progress, "Reusing host disk image: #{path}")
            else
              report_storage_progress(progress, "Creating sparse #{size} disk image: #{path}")
              path = create_disk_image(name, size, format)
            end
            suffix = name == "grml-live-build" ? "live_build" : name.gsub(/[^A-Za-z0-9_-]/, "_")
            node_name = "grml_disk_#{suffix}"
            attached = find_attached_disk_info_by_path(path)
            if attached
              report_storage_progress(progress, "Verifying attached disk image metadata through QMP")
              verify_attached_disk_image(attached, path, format, size)
            else
              report_storage_progress(progress, "QMP does not report image attached by path")
              report_storage_progress(progress, "Verifying detached disk image size and format")
              verify_detached_disk_image(path, format, size, node_name, progress)
            end
            path
          end
        end
      
        module ProvisionExt4Disk
          private def provision_ext4_disk(name, mountpoint, path, progress) : Nil
            report_storage_progress(progress, "Waiting for guest disk and preparing ext4 workspace")
            result = @interaction.execute_streaming(ensure_ext4_provisioning_command(name, mountpoint), 2.minutes) do |_stream, chunk|
              report_storage_output(progress, chunk)
            end
            raise_ext4_disk_provisioning_error(result, path) unless result.success?
            report_storage_progress(progress, "Guest ext4 workspace is mounted and verified")
          end
        end
      
        module RaiseExt4DiskProvisioningError
          private def raise_ext4_disk_provisioning_error(result, path)
            details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
            message = "Could not provision persistent ext4 build workspace (exit=#{result.exit_code})"
            message += ":\n#{details}" unless details.empty?
            raise "#{message}. Disk image is retained at #{path} for recovery."
          end
        end
      
        module ReportMissingExt4Disk
          private def report_missing_ext4_disk : String
            <<-SCRIPT
              report_missing_ext4_disk() {
                echo "Guest block devices:"
                lsblk -o NAME,PATH,TYPE,SIZE,SERIAL,FSTYPE,LABEL,MOUNTPOINTS || true
                echo "Virtio block-device serials:"
                for block in /sys/block/vd*; do
                  [ -d "$block" ] || continue
                  printf '%s serial=' "$block"
                  cat "$block/serial" 2>/dev/null || echo "<unavailable>"
                done
                echo "Virtio by-id links:"
                for link in /dev/disk/by-id/virtio-*; do
                  [ -e "$link" ] || continue
                  printf '%s -> %s\n' "$link" "$(readlink "$link")"
                done
                echo "Recent kernel messages:"
                dmesg | tail -n 60 || true
              }
            SCRIPT
          end
        end
      
        module ReportStorageOutput
          private def report_storage_output(progress : Proc(String, Nil)?, chunk : String) : Nil
            return if chunk.empty?
            if callback = progress
              callback.call(chunk)
            else
              Log.info { chunk }
            end
          end
        end
      
        module ReportStorageProgress
          private def report_storage_progress(progress : Proc(String, Nil)?, message : String) : Nil
            if callback = progress
              callback.call("#{message}\n")
            else
              Log.info { message }
            end
          end
        end
      
        module ShellQuote
          private def shell_quote(value : String) : String
            "'" + value.gsub("'", "'\\''") + "'"
          end
        end
      
        module StorageDiagnosticsPayload
          private def storage_diagnostics_payload(path : String, node_name : String) : String
            JSON.parse({
              "timestamp_utc" => Time.utc.to_s, "image_path" => path,
              "expected_node_name" => node_name,
              "vm" => {"running" => @vm.running?, "display" => @vm.display,
                "iso_path" => @vm.iso_path, "monitor_path" => @vm.monitor_path,
                "monitor_socket_exists" => File.exists?(@vm.monitor_path)},
              "qmp" => storage_qmp_diagnostics,
              "host" => storage_host_diagnostics(path)
            }.to_json).to_json
          end
        end
      
        module StorageHostDiagnostics
          private def storage_host_diagnostics(path : String) : JSON::Any
            owners = capture_storage_command("fuser", [path])
            pids = owners.as_h["stdout"]?.try(&.as_s).to_s.split.compact_map(&.to_i?).uniq
            processes = pids.map { |pid| capture_storage_command("ps", ["-ww", "-p", pid.to_s, "-o", "pid=,ppid=,user=,args="]) }
            JSON.parse({
              "fuser_verbose" => capture_storage_command("fuser", ["-v", path]),
              "fuser_pids" => owners, "owner_processes" => processes,
              "lslocks" => capture_storage_command("lslocks", ["--notruncate", "--output", "PID,COMMAND,TYPE,MODE,PATH"]),
              "qemu_processes" => capture_storage_command("pgrep", ["-af", "qemu-system-x86_64"])
            }.to_json)
          end
        end
      
        module StorageQMPDiagnostics
          private def storage_qmp_diagnostics : JSON::Any
            JSON.parse({
              "query-named-block-nodes" => capture_storage_qmp("query-named-block-nodes"),
              "query-block" => capture_storage_qmp("query-block"),
              "query-status" => capture_storage_qmp("query-status"),
              "query-version" => capture_storage_qmp("query-version")
            }.to_json)
          end
        end
      
        module ValidateDiskFormat
          private def validate_disk_format(format : String) : Nil
            unless DISK_FORMATS.includes?(format)
              raise ArgumentError.new("Unsupported disk format #{format.inspect}; choose qcow2 or raw")
            end
          end
        end
      
        module ValidateDiskName
          private def validate_disk_name(name : String) : Nil
            unless name.matches?(DISK_NAME_PATTERN)
              raise ArgumentError.new("Invalid disk name: #{name.inspect}")
            end
          end
        end
      
        module ValidateGuestMountpoint
          private def validate_guest_mountpoint(path : String) : String
            unless path.starts_with?("/") && path != "/" && !path.split("/").any? { |part| part == "." || part == ".." }
              raise ArgumentError.new("Mount point must be an absolute guest path without '.' or '..' components: #{path.inspect}")
            end
            path
          end
        end
      
        module VerifyAttachedDiskImage
          private def verify_attached_disk_image(inserted : JSON::Any, path : String, format : String, size : String) : Nil
            details = inserted.as_h
            attached_path = details["file"]?.try(&.as_s)
            raise "QMP attachment has no backing-file path" unless attached_path
            raise "QEMU disk attachment path mismatch: #{attached_path}" unless File.expand_path(attached_path) == path
            image = details["image"]?
            raise "QMP attachment has no image metadata" unless image
            actual_format = image.as_h["format"]?.try(&.as_s)
            raise "Attached disk format mismatch: #{actual_format.inspect}, expected #{format}" unless actual_format == format
            actual_bytes = disk_image_virtual_size(image.to_json)
            expected_bytes = expected_disk_image_size(size)
            raise "Attached disk is too small: #{actual_bytes} bytes, #{expected_bytes} required" if actual_bytes < expected_bytes
          end
        end
      
        module VerifyDetachedDiskImage
          private def verify_detached_disk_image(path, format, size, node_name, progress) : Nil
            verify_disk_image_size(path, format, size)
          rescue ex
            begin
              report = write_storage_diagnostics(path, node_name)
              report_storage_progress(progress, "Storage diagnostics written: #{report}")
            rescue diagnostic_error
              raise "#{ex.message}\nCould not write storage diagnostics: #{diagnostic_error.message}"
            end
            raise "#{ex.message}\nStorage diagnostics: #{report}"
          end
        end
      
        module VerifyDiskImageSize
          private def verify_disk_image_size(path : String, format : String, requested_size : String) : Nil
            expected_bytes = expected_disk_image_size(requested_size)
            output, error = IO::Memory.new, IO::Memory.new
            result = Process.run("qemu-img", ["info", "--output=json", "-f", format, path], output: output, error: error)
            unless result.success?
              raise "qemu-img could not inspect #{path} (#{result.exit_code}): #{error}"
            end
            actual_bytes = disk_image_virtual_size(output.to_s)
            if actual_bytes < expected_bytes
              raise "Disk image #{path} is too small: #{actual_bytes} bytes, #{expected_bytes} required"
            end
          end
        end
      
        module VerifyExt4Mount
          private def verify_ext4_mount : String
            <<-SCRIPT
              if mountpoint -q "$mountpoint"; then
                mounted_source=$(findmnt -n -o SOURCE --target "$mountpoint")
                mounted_type=$(findmnt -n -o FSTYPE --target "$mountpoint")
                if [ "$mounted_type" != ext4 ] || [ "$(readlink -f "$mounted_source")" != "$(readlink -f "$partition")" ]; then
                  echo "Build workspace is mounted from another filesystem" >&2
                  exit 1
                fi
                echo "Existing ext4 build workspace is already mounted at $mountpoint"
                exit 0
              fi
            SCRIPT
          end
        end
      
        module WaitForExt4Disk
          private def wait_for_ext4_disk : String
            <<-SCRIPT
              echo "Waiting for guest disk with serial: $serial"
              for attempt in $(seq 1 50); do
                if [ ! -b "$disk" ]; then
                  for serial_file in /sys/block/vd*/serial; do
                    [ -r "$serial_file" ] || continue
                    actual_serial=$(cat "$serial_file")
                    if [ "$actual_serial" = "$serial" ]; then
                      device="${serial_file#/sys/block/}"
                      disk="/dev/${device%%/*}"
                      echo "Found virtio disk by sysfs serial: $disk"
                      break
                    fi
                  done
                fi
                [ -b "$disk" ] && break
                sleep 0.1
              done
              if [ ! -b "$disk" ]; then
                echo "Guest block device did not appear for serial: $serial" >&2
                report_missing_ext4_disk >&2
                exit 1
              fi
              case "$disk" in
                /dev/disk/by-id/*) partition="$disk-part1" ;;
                *) partition="${disk}1" ;;
              esac
              echo "Using guest disk: $disk; partition: $partition"
            SCRIPT
          end
        end
      
        module WriteStorageDiagnostics
          private def write_storage_diagnostics(path : String, node_name : String) : String
            state = ENV["XDG_STATE_HOME"]? || File.join(ENV["HOME"]? || "/tmp", ".local", "state")
            directory = File.join(state, "grml-agent", "storage")
            Dir.mkdir_p(directory)
            name = "build-workspace-#{Time.utc.to_s("%Y%m%dT%H%M%S")}-#{Process.pid}.json"
            report = File.join(directory, name)
            File.write(report, storage_diagnostics_payload(path, node_name))
            report
          end
        end
      
        include AttachDiskWithSerial
        include CreateDiskImage
        include EnsureExt4Disk
        include EnsureExt4ProvisioningCommand
        include ExecuteQMPChecked
        include Ext4ProvisioningCommand
        include FindAttachedDiskInfo
        include FindAttachedDiskInfoByPath
        include FindAttachedDiskPath
        include ShellQuote
        include ValidateDiskFormat
        include ValidateDiskName
        include ValidateGuestMountpoint
        include VerifyDiskImageSize
        include VerifyAttachedDiskImage
        include PrepareExt4DiskImage
        include EnsureExt4DiskAttachment
        include ProvisionExt4Disk
        include RaiseExt4DiskProvisioningError
        include ReportStorageProgress
        include ReportStorageOutput
        include WaitForExt4Disk
        include VerifyExt4Mount
        include CreateExt4Partition
        include FormatExt4Partition
        include MountExt4Partition
        include DiskSizeMultiplier
        include ExpectedDiskImageSize
        include DiskImageVirtualSize
        include CaptureStorageCommand
        include CaptureStorageQMP
        include StorageQMPDiagnostics
        include StorageHostDiagnostics
        include StorageDiagnosticsPayload
        include WriteStorageDiagnostics
        include VerifyDetachedDiskImage
        include ReportMissingExt4Disk
      end
    
      module Public
        module AttachDisk
          def attach_disk(path : String, format : String = "qcow2") : String
            attach_disk_with_serial(path, format)[:device_id]
          end
        end
      
        module CreateDisk
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
        end
      
        module CreateExt4Disk
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
        end
      
        include CreateDisk
        include CreateExt4Disk
        include AttachDisk
      end
    
      DISK_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
      DISK_SIZE_PATTERN = /\A[1-9][0-9]*(?:[KMGTP])?\z/i
      DISK_FORMATS = ["qcow2", "raw"]
      
      include Public
      include Private
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
  
    module ValidateBuildProfile
      BUILD_PROFILE_ROOT = "/mnt/shared/profiles"
      BUILD_PROFILE_BUILDER_PACKAGES = "builder-packages.txt"
      BUILD_PROFILE_BUILTIN_CLASSES = LiveBuildManifest::BUILTIN_CLASSES
      BUILD_PROFILE_CONFIG_DIRECTORIES = %w(bootstrap-keyring package_config debconf env files hooks scripts media-files media-scripts tools)
      
      def validate_profile(profile_name : String, progress : Proc(String, Nil)? = nil) : LiveBuildManifest
        validate_build_profile_name(profile_name)
        profile_directory = "#{BUILD_PROFILE_ROOT}/#{profile_name}"
        manifest_path = "#{profile_directory}/grml-live/build.yml"
      
        verify_profile_tree(profile_directory)
        report_build_profile_progress(progress, "Reading grml-live build manifest for '#{profile_name}'")
        manifest = read_build_manifest(manifest_path)
        manifest.validate!
      
        report_build_profile_progress(progress, "Validating builder package list")
        packages = read_builder_packages(profile_directory)
        report_build_profile_progress(progress, "Builder packages: #{packages.size}")
      
        report_build_profile_progress(progress, "Checking custom grml-live classes")
        validate_profile_classes(profile_directory, manifest)
        report_build_profile_progress(progress, "Profile '#{profile_name}' is valid")
        manifest
      end
      
      private def validate_build_profile_name(profile_name : String) : Nil
        unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
      end
      
      private def verify_profile_tree(profile_directory : String) : Nil
        command = <<-SHELL
          set -eu
          if [ ! -d '#{profile_directory}' ]; then
            echo "Profile directory not found: #{profile_directory}" >&2
            exit 2
          fi
          if [ ! -f '#{profile_directory}/grml-live/build.yml' ]; then
            echo "Missing grml-live build manifest: #{profile_directory}/grml-live/build.yml" >&2
            exit 2
          fi
          SHELL
        result = @interaction.execute(command)
        unless result.success?
          raise "Profile directory validation failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
      end
      
      private def read_build_manifest(path : String) : LiveBuildManifest
        command = <<-SHELL
          set -eu
          manifest='#{path}'
          if [ ! -f "$manifest" ]; then
            echo "Missing grml-live build manifest: $manifest" >&2
            exit 2
          fi
          python3 - "$manifest" <<'PY'
          import datetime
          import json
          import sys
          import yaml
      
          allowed = {
              "suite", "classes", "hostname", "username", "distri_name",
              "distri_info", "grml_name", "release_name", "version",
              "boot_options", "secure_boot", "release", "bootstrap_mirror_url",
              "grml_live_ref", "iso_name", "date", "wayback_date", "source_date_epoch",
          }
      
          def normalize(value):
              if isinstance(value, (datetime.date, datetime.datetime)):
                  return value.isoformat()
              raise TypeError(f"Unsupported YAML value: {type(value).__name__}")
      
          try:
              with open(sys.argv[1], encoding="utf-8") as manifest_file:
                  data = yaml.safe_load(manifest_file)
              if not isinstance(data, dict):
                  raise ValueError("Manifest root must be a YAML mapping")
              unknown = sorted(set(data) - allowed)
              if unknown:
                  raise ValueError("Unknown manifest key(s): " + ", ".join(unknown))
              print(json.dumps(data, default=normalize))
          except Exception as error:
              print(f"Invalid grml-live build manifest: {error}", file=sys.stderr)
              sys.exit(3)
          PY
          SHELL
      
        result = @interaction.execute(command, 30.seconds)
        unless result.success?
          raise "Could not read grml-live build manifest (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
      
        LiveBuildManifest.from_json(result.stdout)
      rescue ex : JSON::ParseException
        raise "Could not parse grml-live build manifest JSON: #{ex.message}"
      end
      
      private def read_builder_packages(profile_directory : String) : Array(String)
        packages_file = "#{profile_directory}/#{BUILD_PROFILE_BUILDER_PACKAGES}"
        command = <<-SHELL
          set -eu
          packages_file='#{packages_file}'
          [ -f "$packages_file" ] || exit 0
          awk '
            {
              sub(/#.*/, "")
              gsub(/^[[:space:]]+|[[:space:]]+$/, "")
              if ($0 == "") next
              if ($0 !~ /^[a-z0-9][a-z0-9+.-]*$/) {
                printf "Invalid Debian builder package name on line %d: %s\\\\n", NR, $0 > "/dev/stderr"
                exit 2
              }
              print
            }
          ' "$packages_file"
          SHELL
        result = @interaction.execute(command)
        unless result.success?
          raise "Could not read builder package list (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
      
        result.stdout.lines.map(&.strip).reject(&.empty?).uniq
      end
      
      private def validate_profile_classes(profile_directory : String, manifest : LiveBuildManifest) : Nil
        custom_classes = manifest.classes.reject { |class_name| BUILD_PROFILE_BUILTIN_CLASSES.includes?(class_name) }
        return if custom_classes.empty?
      
        config_directory = "#{profile_directory}/grml-live/config"
        command = <<-SHELL
          set -eu
          config='#{config_directory}'
          for class_name in #{custom_classes.map { |name| shell_quote(name) }.join(" ")}; do
            found=0
            for category in #{BUILD_PROFILE_CONFIG_DIRECTORIES.join(" ")}; do
              if [ -e "$config/$category/$class_name" ]; then
                found=1
                break
              fi
            done
            if [ "$found" -ne 1 ]; then
              echo "Custom class '$class_name' has no definition under $config" >&2
              exit 4
            fi
          done
          SHELL
      
        result = @interaction.execute(command)
        unless result.success?
          raise "Profile class validation failed (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
      end
      
      private def shell_quote(value : String) : String
        "'" + value.gsub("'", "'\\\\''") + "'"
      end
      
      private def report_build_profile_progress(progress : Proc(String, Nil)?, message : String) : Nil
        if callback = progress
          callback.call("#{message}\\n")
        else
          Log.info { message }
        end
      end
    end
  
    module VerifyDebCache
      DEB_CACHE_VERIFY_OFFLINE_CONFIG = "/etc/apt-cacher-ng/zzzzzz-grml-agent-verify.conf"
      
      def verify_deb_cache(package : String = "hello", progress : Proc(String, Nil)? = nil) : Nil
        unless package.matches?(/\A[a-z0-9][a-z0-9+.-]*\z/)
          raise ArgumentError.new("Invalid Debian package name: #{package.inspect}")
        end
      
        started_at = Time.instant
        run_id = Random.rand(0_i64..Int64::MAX).to_s
        work_directory = "/tmp/grml-agent-deb-cache-verify-#{run_id}"
        offline_config = DEB_CACHE_VERIFY_OFFLINE_CONFIG
        offline_mode_may_be_enabled = false
      
        report_deb_cache_verification_progress(progress, "Verifying shared Debian package cache")
        report_deb_cache_verification_progress(progress, "Package: #{package}")
      
        begin
          report_deb_cache_verification_stage(1, "Checking proxy and APT configuration", progress) do
            command = <<-BASH
              set -eu
              if ! mountpoint -q /mnt/shared; then
                echo "The QEMU shared directory is not mounted at /mnt/shared" >&2
                exit 20
              fi
      
              if ! runuser -u apt-cacher-ng -- test -w /mnt/shared/deb-cache/proxy; then
                echo "apt-cacher-ng cannot write to /mnt/shared/deb-cache/proxy" >&2
                exit 22
              fi
      
              # Recover from an interrupted verification before starting a new one.
              rm -f '#{offline_config}'
              systemctl restart apt-cacher-ng
      
              if ! apt-config dump | grep -Fqx 'Acquire::http::Proxy "http://127.0.0.1:3142";'; then
                echo "APT is not configured to use the shared-cache proxy" >&2
                exit 23
              fi
      
              ready=0
              for attempt in $(seq 1 15); do
                if systemctl is-active --quiet apt-cacher-ng &&
                   curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
                  ready=1
                  break
                fi
                sleep 1
              done
      
              if [ "$ready" -ne 1 ]; then
                systemctl --no-pager --full status apt-cacher-ng >&2 || true
                journalctl -u apt-cacher-ng -n 40 --no-pager >&2 || true
                echo "apt-cacher-ng is not ready" >&2
                exit 21
              fi
      
              echo "APT HTTP proxy and apt-cacher-ng are ready"
            BASH
            run_deb_cache_verification_command(command)
          end
      
          report_deb_cache_verification_stage(2, "Downloading the current package version", progress) do
            command = <<-BASH
              set -eu
              work_directory='#{work_directory}'
              package='#{package}'
              mkdir -m 0700 -p "$work_directory/online" "$work_directory/offline"
      
              apt-get update
              version=$(apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')
              if [ -z "$version" ] || [ "$version" = "(none)" ]; then
                echo "No candidate version is available for package: $package" >&2
                exit 40
              fi
      
              download_log="$work_directory/online/download.log"
              if ! (cd "$work_directory/online" && apt-get download "$package=$version") 2>&1 | tee "$download_log"; then
                echo "APT could not download $package=$version" >&2
                exit 41
              fi
      
              if ! grep -Eq 'Get:[[:space:]]*[0-9]+[[:space:]]+http://' "$download_log"; then
                echo "The package was not fetched from an HTTP repository; this HTTP cache cannot verify HTTPS package payloads" >&2
                exit 42
              fi
      
              archive=$(find "$work_directory/online" -maxdepth 1 -type f -name '*.deb' -print -quit)
              if [ -z "$archive" ]; then
                echo "APT completed without producing a .deb archive" >&2
                exit 43
              fi
      
              checksum=$(sha256sum "$archive" | awk '{print $1}')
              bytes=$(stat -c '%s' "$archive")
              printf '%s\n%s\n' "$version" "$checksum" > "$work_directory/metadata"
              printf 'Package: %s\nVersion: %s\nFirst download SHA-256: %s\nArchive size: %s bytes\n' \
                "$package" "$version" "$checksum" "$bytes"
            BASH
            run_deb_cache_verification_command(command, 10.minutes, progress)
          end
      
          offline_mode_may_be_enabled = true
          report_deb_cache_verification_stage(3, "Disabling upstream access", progress) do
            command = <<-BASH
              set -eu
              printf '%s\\n' 'Offlinemode: 1' > '#{offline_config}'
      
              systemctl restart apt-cacher-ng
              ready=0
              for attempt in $(seq 1 15); do
                if systemctl is-active --quiet apt-cacher-ng &&
                   curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
                  ready=1
                  break
                fi
                sleep 1
              done
      
              if [ "$ready" -ne 1 ]; then
                systemctl --no-pager --full status apt-cacher-ng >&2 || true
                journalctl -u apt-cacher-ng -n 40 --no-pager >&2 || true
                echo "apt-cacher-ng did not restart in offline mode" >&2
                exit 44
              fi
      
              echo "apt-cacher-ng is active with Offlinemode: 1"
            BASH
            run_deb_cache_verification_command(command, 30.seconds)
          end
      
          report_deb_cache_verification_stage(4, "Fetching the same version with upstream disabled", progress) do
            command = <<-BASH
              set -eu
              work_directory='#{work_directory}'
              package='#{package}'
              version=$(sed -n '1p' "$work_directory/metadata")
              expected_checksum=$(sed -n '2p' "$work_directory/metadata")
              download_log="$work_directory/offline/download.log"
      
              if [ -z "$version" ] || [ -z "$expected_checksum" ]; then
                echo "Missing metadata from the first package download" >&2
                exit 45
              fi
      
              if ! (cd "$work_directory/offline" && apt-get download "$package=$version") 2>&1 | tee "$download_log"; then
                echo "The package was not available from the cache while upstream access was disabled" >&2
                exit 46
              fi
      
              if ! grep -Eq 'Get:[[:space:]]*[0-9]+[[:space:]]+http://' "$download_log"; then
                echo "The offline package request did not use an HTTP repository URL" >&2
                exit 47
              fi
      
              archive=$(find "$work_directory/offline" -maxdepth 1 -type f -name '*.deb' -print -quit)
              if [ -z "$archive" ]; then
                echo "Offline APT download completed without producing a .deb archive" >&2
                exit 48
              fi
      
              actual_checksum=$(sha256sum "$archive" | awk '{print $1}')
              if [ "$actual_checksum" != "$expected_checksum" ]; then
                echo "Cached package checksum does not match the first download" >&2
                echo "Expected: $expected_checksum" >&2
                echo "Actual:   $actual_checksum" >&2
                exit 49
              fi
      
              printf 'Offline download SHA-256: %s\nCache verification: PASS (upstream disabled)\n' \
                "$actual_checksum"
            BASH
            run_deb_cache_verification_command(command, 5.minutes, progress)
          end
      
          report_deb_cache_verification_stage(5, "Restoring normal proxy mode", progress) do
            result = run_deb_cache_verification_command(restore_deb_cache_proxy_command(offline_config), 30.seconds)
            offline_mode_may_be_enabled = false
            result
          end
      
          elapsed = Time.instant - started_at
          report_deb_cache_verification_progress(progress, "Shared Debian package cache verified for #{package}")
          report_deb_cache_verification_progress(progress, "The same package version was downloaded successfully with upstream access disabled")
          report_deb_cache_verification_progress(progress, "Total verification time: #{elapsed.total_seconds.round(1)}s")
        rescue ex
          report_deb_cache_verification_progress(progress, "Package cache verification FAILED: #{ex.message}")
          raise ex
        ensure
          if offline_mode_may_be_enabled
            begin
              cleanup_result = @interaction.execute(restore_deb_cache_proxy_command(offline_config), 30.seconds)
              if cleanup_result.success?
                report_deb_cache_verification_progress(progress, "Restored normal apt-cacher-ng mode after verification failure")
              else
                report_deb_cache_verification_progress(
                  progress,
                  "WARNING: could not restore apt-cacher-ng online mode: #{cleanup_result.stderr}\n#{cleanup_result.stdout}"
                )
              end
            rescue cleanup_error
              report_deb_cache_verification_progress(
                progress,
                "WARNING: could not restore apt-cacher-ng online mode: #{cleanup_error.message}"
              )
            end
          end
      
          begin
            cleanup_result = @interaction.execute("rm -rf '#{work_directory}'", 30.seconds)
            unless cleanup_result.success?
              report_deb_cache_verification_progress(progress, "WARNING: could not remove verification directory #{work_directory}")
            end
          rescue cleanup_error
            report_deb_cache_verification_progress(
              progress,
              "WARNING: could not remove verification directory #{work_directory}: #{cleanup_error.message}"
            )
          end
        end
      end
      
      private def restore_deb_cache_proxy_command(offline_config : String) : String
        <<-BASH
          set -eu
          rm -f '#{offline_config}'
          systemctl restart apt-cacher-ng
      
          ready=0
          for attempt in $(seq 1 15); do
            if systemctl is-active --quiet apt-cacher-ng &&
               curl -fsS --max-time 2 http://127.0.0.1:3142/acng-report.html >/dev/null 2>&1; then
              ready=1
              break
            fi
            sleep 1
          done
      
          if [ "$ready" -ne 1 ]; then
            systemctl --no-pager --full status apt-cacher-ng >&2 || true
            journalctl -u apt-cacher-ng -n 40 --no-pager >&2 || true
            echo "apt-cacher-ng did not return to online mode" >&2
            exit 50
          fi
      
          echo "apt-cacher-ng is active with normal upstream access"
        BASH
      end
      
      private def report_deb_cache_verification_stage(
        index : Int32,
        title : String,
        progress : Proc(String, Nil)?,
        &block : -> String
      ) : Nil
        label = "[#{index}/5] #{title}"
        started_at = Time.instant
        report_deb_cache_verification_progress(progress, "#{label} ...")
      
        begin
          details = yield
        rescue ex
          elapsed = Time.instant - started_at
          report_deb_cache_verification_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
          raise "Failed during #{title}: #{ex.message}"
        end
      
        elapsed = Time.instant - started_at
        report_deb_cache_verification_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
        report_deb_cache_verification_progress(progress, details) unless details.empty?
      end
      
      private def run_deb_cache_verification_command(
        command : String,
        timeout : Time::Span = 30.seconds,
        progress : Proc(String, Nil)? = nil
      ) : String
        result = @interaction.execute_streaming(command, timeout) do |_stream, chunk|
          report_deb_cache_verification_output(progress, chunk)
        end
        unless result.success?
          raise "Guest command failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
        end
      
        ""
      end
      
      private def report_deb_cache_verification_output(progress : Proc(String, Nil)?, chunk : String) : Nil
        return if chunk.empty?
      
        if callback = progress
          callback.call(chunk)
        else
          Log.info { chunk }
        end
      end
      
      private def report_deb_cache_verification_progress(
        progress : Proc(String, Nil)?,
        message : String
      ) : Nil
        if callback = progress
          callback.call("#{message}\n")
        else
          Log.info { message }
        end
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
    
    include ApplyProfile
    include Boot
    include VerifySharedDirectory
    include PrepareAlpineBundle
    include PrepareDebCache
    include VerifyDebCache
    include ValidateBuildProfile
    include PrepareBuildEnvironment
    include BuildISO
    include Storage
    include CopyExecutableToGuest
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
        STDERR.puts "Usage: grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH] | tmux [--iso PATH] | prepare_alpine_bundle [alpine_branch]"
        exit 1
      end
    end
  
    class Act
      getter arguments : Array(String)
      getter boot_iso_path : String?
      getter boot_profile : String?
      getter boot_verify_deb_cache : Bool
      
      def initialize(@arguments : Array(String) = [] of String)
        @boot_iso_path = nil
        @boot_profile = nil
        @boot_verify_deb_cache = false
        validate_arguments
      end
      
      def validate_arguments
      end
      
      def run : Nil
        agent = GRML::Agent.new(@boot_iso_path)
        Signal::INT.trap { agent.terminate && exit }
        Signal::TERM.trap { agent.terminate && exit }
        begin
          agent.boot(@boot_profile, @boot_verify_deb_cache)
          perform(agent)
        ensure
          agent.terminate
        end
      end
      
      protected def perform(agent : GRML::Agent) : Nil
      end
    
      class Boot < Act
        def validate_arguments
          args = @arguments.dup
          until args.empty?
            argument = args.shift
            case argument
            when "--iso"
              if args.empty? || @boot_iso_path
                usage_error
              end
              @boot_iso_path = args.shift
            when "--verify-deb-cache"
              if @boot_verify_deb_cache
                usage_error
              end
              @boot_verify_deb_cache = true
            else
              if argument.starts_with?("-") || @boot_profile
                usage_error
              end
              unless argument.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
                usage_error
              end
              @boot_profile = argument
            end
          end
        
          usage_error if @boot_verify_deb_cache && !@boot_profile
        end
        
        private def usage_error : NoReturn
          STDERR.puts "Usage: grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]"
          exit 1
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

  class LiveBuildManifest
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
      property wayback_date : String? = nil
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
          wayback_date: data["wayback_date"]?.try(&.as_s?),
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
        @wayback_date : String? = nil,
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
    
        if snapshot = wayback_date
          unless snapshot.matches?(/\A[0-9]{8}(?:T[0-9]{6}Z)?\z/)
            raise ArgumentError.new("wayback_date must use YYYYMMDD or YYYYMMDDTHHMMSSZ format")
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
  end

  class REPL
    module ApplyProfile
      def apply_profile(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        unless arguments.size == 1
          raise ArgumentError.new("Usage: apply_profile PROFILE_NAME")
        end
      
        profile_name = arguments.first
        unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
      
        agent.verify_shared_directory
        agent.apply_profile(profile_name, false, progress)
        "Applied package profile '#{profile_name}'. Package installation is additive; other packages are not removed."
      end
    end
  
    module BuildDefinition
      def build_definition(agent : T) : TmuxREPL::Definition forall T
        Definition.build(agent)
      end
    end
  
    module BuildISO
      def build_iso(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        unless arguments.size == 1
          raise ArgumentError.new("Usage: build_iso PROFILE_NAME")
        end
      
        profile_name = arguments.first
        unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
      
        agent.verify_shared_directory
        agent.build_iso(profile_name, progress)
      end
    end
  
    module CopyExecutable
      def copy_executable(agent : T, arguments : Array(String)) : String forall T
        unless arguments.size == 2
          raise ArgumentError.new("Usage: copy_executable <host_path> <guest_path>")
        end
        source = arguments[0]
        destination = arguments[1]
        agent.copy_executable_to_guest(source, destination)
        "Copied executable #{source} to guest at #{destination} (mode 0755)."
      end
    end
  
    module PrepareAlpineBundle
      DEFAULT_ALPINE_BRANCH = "latest-stable"
      
      def alpine_branch(arguments : Array(String)) : String
        raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]") if arguments.size > 1
        branch = arguments.first? || DEFAULT_ALPINE_BRANCH
        raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}") unless branch =~ /\A[a-zA-Z0-9._-]+\z/
        branch
      end
      
      def prepare_alpine_bundle(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        branch = alpine_branch(arguments)
        agent.prepare_alpine_bundle(branch, progress)
        "Prepared Alpine offline bundle (branch: #{branch})."
      end
    end
  
    module PrepareBuildEnvironment
      def prepare_build_environment(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        unless arguments.size == 1
          raise ArgumentError.new("Usage: prepare_build_environment PROFILE_NAME")
        end
      
        profile_name = arguments.first
        unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
      
        agent.verify_shared_directory
        agent.prepare_build_environment(profile_name, progress)
        "Prepared grml-live build environment for '#{profile_name}'."
      end
    end
  
    module PrepareDebCache
      DEFAULT_DEB_CACHE_DIRECTORY = "/mnt/shared/deb-cache"
      
      def prepare_deb_cache(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        raise ArgumentError.new("Usage: prepare_deb_cache") unless arguments.empty?
      
        agent.prepare_deb_cache(progress)
        "Prepared shared Debian package cache at #{DEFAULT_DEB_CACHE_DIRECTORY}."
      end
    end
  
    module Questions
      def focus? : Bool
        value = ENV.fetch(GRML::REPL::FOCUS_ENV, "true").strip.downcase
        case value
        when "1", "true", "yes", "on" then true
        when "0", "false", "no", "off" then false
        else raise ArgumentError.new("#{GRML::REPL::FOCUS_ENV} must be a boolean; got #{value.inspect}")
        end
      end
    end
  
    module Run
      def run(agent : Agent) : Nil
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
  
    module ValidateProfile
      def validate_profile(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        unless arguments.size == 1
          raise ArgumentError.new("Usage: validate_profile PROFILE_NAME")
        end
      
        profile_name = arguments.first
        unless profile_name.matches?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/)
          raise ArgumentError.new("Invalid profile name: #{profile_name.inspect}")
        end
      
        agent.verify_shared_directory
        manifest = agent.validate_profile(profile_name, progress)
        "Validated '#{profile_name}': suite=#{manifest.suite}, classes=#{manifest.classes_argument}."
      end
    end
  
    module VerifyDebCache
      DEFAULT_DEB_CACHE_VERIFICATION_PACKAGE = "hello"
      
      def verify_deb_cache(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
        if arguments.size > 1
          raise ArgumentError.new("Usage: verify_deb_cache [package]")
        end
      
        package = arguments.first? || DEFAULT_DEB_CACHE_VERIFICATION_PACKAGE
        unless package.matches?(/\A[a-z0-9][a-z0-9+.-]*\z/)
          raise ArgumentError.new("Invalid Debian package name: #{package.inspect}")
        end
      
        agent.verify_deb_cache(package, progress)
        "Verified shared Debian package cache using #{package}."
      end
    end
  
    FOCUS_ENV = "GRML_AGENT_REPL_FOCUS"
    
    extend Questions
    extend PrepareAlpineBundle
    extend PrepareDebCache
    extend ApplyProfile
    extend PrepareBuildEnvironment
    extend ValidateProfile
    extend BuildISO
    extend VerifyDebCache
    extend CopyExecutable
    extend BuildDefinition
    extend Run
  
    module Commands
    
      module ApplyProfile
        NAME = "apply_profile"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.apply_profile(agent, arguments, progress)
          end
          nil
        end
      end
    
      module AttachDisk
        NAME = "attach_disk"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            unless (1..2).includes?(arguments.size)
              raise ArgumentError.new("Usage: attach_disk <path> [qcow2|raw]")
            end
        
            format = arguments[1]? || "qcow2"
            device_id = agent.attach_disk(arguments[0], format)
            context.puts("Attached #{File.expand_path(arguments[0])} as #{device_id}")
          end
          nil
        end
      end
    
      module BuildISO
        NAME = "build_iso"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.build_iso(agent, arguments, progress)
          end
          nil
        end
      end
    
      module CopyExecutable
        NAME = "copy_executable"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            context.puts(GRML::REPL.copy_executable(agent, arguments))
          end
          nil
        end
      end
    
      module CreateDisk
        NAME = "create_disk"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            unless (2..3).includes?(arguments.size)
              raise ArgumentError.new("Usage: create_disk <name> <size> [qcow2|raw]")
            end
        
            format = arguments[2]? || "qcow2"
            path = agent.create_disk(arguments[0], arguments[1], format)
            context.puts("Created and attached #{path}")
          end
          nil
        end
      end
    
      module CreateExt4Disk
        NAME = "create_ext4_disk"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
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
          nil
        end
      end
    
      module GuestExec
        NAME = "guest_exec"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            raise ArgumentError.new("Usage: guest_exec <shell command>") if arguments.empty?
        
            command = arguments.join(" ")
            result = agent.interaction.execute_streaming(command, 2.minutes) do |_stream, chunk|
              context.write(chunk) unless chunk.empty?
            end
            context.puts("Guest command exited with status #{result.exit_code}") unless result.success?
          end
          nil
        end
      end
    
      module OCR
        NAME = "ocr"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            raise ArgumentError.new("Usage: ocr") unless arguments.empty?
        
            result = agent.interaction.latest_ocr
            if error = result.error
              raise "OCR failed for frame #{result.timestamp}: #{error}"
            end
        
            result.text.strip.empty? ? context.puts("(no text recognized)") : context.write(result.text)
          end
          nil
        end
      end
    
      module PrepareAlpineBundle
        NAME = "prepare_alpine_bundle"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
            nil
          end
          nil
        end
      end
    
      module PrepareBuildEnvironment
        NAME = "prepare_build_environment"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.prepare_build_environment(agent, arguments, progress)
          end
          nil
        end
      end
    
      module PrepareDebCache
        NAME = "prepare_deb_cache"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.prepare_deb_cache(agent, arguments, progress)
          end
          nil
        end
      end
    
      module ValidateProfile
        NAME = "validate_profile"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.validate_profile(agent, arguments, progress)
          end
          nil
        end
      end
    
      module VerifyDebCache
        NAME = "verify_deb_cache"
        
        def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
          repl.on_command(NAME) do |context, arguments|
            progress = ->(message : String) { context.write(message) }
            GRML::REPL.verify_deb_cache(agent, arguments, progress)
          end
          nil
        end
      end
    end
  
    class Definition
      def self.build(agent : T) : TmuxREPL::Definition forall T
        TmuxREPL.define("grml") do |repl|
          GRML::REPL::Commands::OCR.register(repl, agent)
          GRML::REPL::Commands::GuestExec.register(repl, agent)
          GRML::REPL::Commands::CopyExecutable.register(repl, agent)
          GRML::REPL::Commands::PrepareAlpineBundle.register(repl, agent)
          GRML::REPL::Commands::PrepareDebCache.register(repl, agent)
          GRML::REPL::Commands::ApplyProfile.register(repl, agent)
          GRML::REPL::Commands::PrepareBuildEnvironment.register(repl, agent)
          GRML::REPL::Commands::ValidateProfile.register(repl, agent)
          GRML::REPL::Commands::BuildISO.register(repl, agent)
          GRML::REPL::Commands::VerifyDebCache.register(repl, agent)
          GRML::REPL::Commands::CreateDisk.register(repl, agent)
          GRML::REPL::Commands::AttachDisk.register(repl, agent)
          GRML::REPL::Commands::CreateExt4Disk.register(repl, agent)
        end
      end
    end
  end
end