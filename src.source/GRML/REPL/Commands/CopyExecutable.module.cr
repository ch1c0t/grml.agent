NAME = "copy_executable"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    context.puts(GRML::REPL.copy_executable(agent, arguments))
  end
  nil
end
