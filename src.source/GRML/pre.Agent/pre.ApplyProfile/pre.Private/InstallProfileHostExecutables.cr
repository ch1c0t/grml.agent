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
