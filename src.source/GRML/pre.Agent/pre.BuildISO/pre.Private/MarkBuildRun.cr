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
