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
