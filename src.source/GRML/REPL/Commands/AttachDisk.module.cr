NAME = "attach_disk"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    unless (1..2).includes?(arguments.size)
      raise ArgumentError.new("Usage: attach_disk <path> [qcow2|raw]")
    end

    format = arguments[1]? || "qcow2"
    device_id = agent.attach_disk(arguments[0], format)
    context.puts("Attached #{File.expand_path(arguments[0])} as #{device_id}")
  end
  nil
end
