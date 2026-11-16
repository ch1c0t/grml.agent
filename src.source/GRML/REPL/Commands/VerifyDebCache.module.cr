NAME = "verify_deb_cache"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    progress = ->(message : String) { context.write(message) }
    GRML::REPL.verify_deb_cache(agent, arguments, progress)
  end
  nil
end
