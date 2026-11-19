NAME = "prepare_build_environment"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    progress = ->(message : String) { context.write(message) }
    GRML::REPL.prepare_build_environment(agent, arguments, progress)
  end
  nil
end
