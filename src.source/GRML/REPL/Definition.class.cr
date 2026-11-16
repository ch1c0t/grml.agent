def self.build(agent : T) : TmuxREPL::Definition forall T
  TmuxREPL.define("grml") do |repl|
    GRML::REPL::Commands::OCR.register(repl, agent)
    GRML::REPL::Commands::GuestExec.register(repl, agent)
    GRML::REPL::Commands::PrepareAlpineBundle.register(repl, agent)
    GRML::REPL::Commands::PrepareDebCache.register(repl, agent)
    GRML::REPL::Commands::VerifyDebCache.register(repl, agent)
    GRML::REPL::Commands::CreateDisk.register(repl, agent)
    GRML::REPL::Commands::AttachDisk.register(repl, agent)
    GRML::REPL::Commands::CreateExt4Disk.register(repl, agent)
  end
end
