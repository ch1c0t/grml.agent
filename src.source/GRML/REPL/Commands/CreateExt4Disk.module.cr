NAME = "create_ext4_disk"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    unless (2..4).includes?(arguments.size)
      raise ArgumentError.new("Usage: create_ext4_disk <name> <size> [mountpoint] [qcow2|raw]")
    end

    mountpoint = nil
    format = "qcow2"
    if optional = arguments[2]?
      if optional == "qcow2" || optional == "raw"
        format = optional
      else
        mountpoint = optional
        format = arguments[3]? || "qcow2"
      end
    end

    result = agent.create_ext4_disk(arguments[0], arguments[1], mountpoint, format)
    context.puts("Created, partitioned, formatted, and mounted #{result}")
  end
  nil
end
