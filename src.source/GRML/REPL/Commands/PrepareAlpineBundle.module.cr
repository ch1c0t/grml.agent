NAME = "prepare_alpine_bundle"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    progress = ->(message : String) { context.puts(message) }
    GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
    nil
  end
  nil
end
