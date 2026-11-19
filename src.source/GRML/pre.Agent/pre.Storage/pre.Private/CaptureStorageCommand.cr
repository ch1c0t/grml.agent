private def capture_storage_command(command : String, arguments : Array(String)) : JSON::Any
  output, error = IO::Memory.new, IO::Memory.new
  result = Process.run(command, arguments, output: output, error: error)
  JSON.parse({"argv" => [command] + arguments, "exit_code" => result.exit_code, "stdout" => output.to_s, "stderr" => error.to_s}.to_json)
rescue ex
  JSON.parse({"argv" => [command] + arguments, "error" => ex.message}.to_json)
end
