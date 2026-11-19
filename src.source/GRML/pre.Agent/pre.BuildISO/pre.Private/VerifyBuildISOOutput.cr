private def verify_build_iso_output(shared_output_directory : String) : Nil
  command = "find '#{shared_output_directory}/grml_isos' -maxdepth 1 -type f -name '*.iso' -print -quit | grep -q ."
  result = @interaction.execute(command)
  unless result.success?
    raise "grml-live returned success but no ISO file was found in #{shared_output_directory}/grml_isos"
  end
end
