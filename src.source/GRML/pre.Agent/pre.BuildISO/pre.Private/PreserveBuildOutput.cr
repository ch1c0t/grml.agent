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
