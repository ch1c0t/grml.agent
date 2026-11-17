getter arguments : Array(String)
getter boot_iso_path : String?
getter boot_profile : String?

def initialize(@arguments : Array(String) = [] of String)
  @boot_iso_path = nil
  @boot_profile = nil
  validate_arguments
end

def validate_arguments
end

def run : Nil
  agent = GRML::Agent.new(@boot_iso_path)
  Signal::INT.trap { agent.terminate && exit }
  Signal::TERM.trap { agent.terminate && exit }
  begin
    agent.boot(@boot_profile)
    perform(agent)
  ensure
    agent.terminate
  end
end

protected def perform(agent : GRML::Agent) : Nil
end
