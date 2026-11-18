private def execute_qmp_checked(command : String, arguments : Hash(String, JSON::Any)) : JSON::Any
  response = @vm.execute_qmp(command, arguments)
  if error = response.as_h["error"]?
    raise "QMP #{command} failed: #{error}"
  end
  response
end
