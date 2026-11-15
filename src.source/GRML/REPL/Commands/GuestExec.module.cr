NAME = "guest_exec"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    raise ArgumentError.new("Usage: guest_exec <shell command>") if arguments.empty?

    command = arguments.join(" ")
    result = agent.interaction.execute(command, 2.minutes)
    context.write(result.stdout) unless result.stdout.empty?
    context.write(result.stderr) unless result.stderr.empty?
    context.puts("Guest command exited with status #{result.exit_code}") unless result.success?
  end
  nil
end
