NAME = "apply_profile"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    progress = ->(message : String) { context.write(message) }
    GRML::REPL.apply_profile(agent, arguments, progress)
  end
  nil
end
