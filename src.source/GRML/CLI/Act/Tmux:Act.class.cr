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
  sleep 0.5

  Log.info { "Starting the host-side GRML Tmux REPL" }
  GRML::REPL.run(agent)
end
