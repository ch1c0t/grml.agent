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
