FOCUS_ENV = "GRML_AGENT_REPL_FOCUS"
DEFAULT_ALPINE_BRANCH = "latest-stable"

def self.focus? : Bool
  value = ENV.fetch(FOCUS_ENV, "true").strip.downcase
  case value
  when "1", "true", "yes", "on" then true
  when "0", "false", "no", "off" then false
  else raise ArgumentError.new("#{FOCUS_ENV} must be a boolean; got #{value.inspect}")
  end
end

def self.alpine_branch(arguments : Array(String)) : String
  raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]") if arguments.size > 1
  branch = arguments.first? || DEFAULT_ALPINE_BRANCH
  raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}") unless branch =~ /\A[a-zA-Z0-9._-]+\z/
  branch
end

def self.prepare_alpine_bundle(agent : T, arguments : Array(String), progress : Proc(String, Nil)? = nil) : String forall T
  branch = alpine_branch(arguments)
  agent.prepare_alpine_bundle(branch, progress)
  "Prepared Alpine offline bundle (branch: #{branch})."
end

def self.build_definition(agent : T) : TmuxREPL::Definition forall T
  TmuxREPL.define("grml") do |repl|
    repl.on_command("ocr") do |context, arguments|
      raise ArgumentError.new("Usage: ocr") unless arguments.empty?
      result = agent.interaction.latest_ocr
      if error = result.error
        raise "OCR failed for frame #{result.timestamp}: #{error}"
      end
      result.text.strip.empty? ? context.puts("(no text recognized)") : context.write(result.text)
    end

    repl.on_command("prepare_alpine_bundle") do |context, arguments|
      progress = ->(message : String) { context.puts(message) }
      GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
      nil
    end

    repl.on_command("create_disk") do |context, arguments|
      unless (2..3).includes?(arguments.size)
        raise ArgumentError.new("Usage: create_disk <name> <size> [qcow2|raw]")
      end
      format = arguments[2]? || "qcow2"
      path = agent.create_disk(arguments[0], arguments[1], format)
      context.puts("Created and attached #{path}")
    end

    repl.on_command("attach_disk") do |context, arguments|
      unless (1..2).includes?(arguments.size)
        raise ArgumentError.new("Usage: attach_disk <path> [qcow2|raw]")
      end
      format = arguments[1]? || "qcow2"
      device_id = agent.attach_disk(arguments[0], format)
      context.puts("Attached #{File.expand_path(arguments[0])} as #{device_id}")
    end
  end
end

def self.run(agent : Agent) : Nil
  definition = build_definition(agent)
  started = false

  Signal::INT.trap do
    begin
      definition.stop if started
    ensure
      agent.terminate
      exit
    end
  end
  Signal::TERM.trap do
    begin
      definition.stop if started
    ensure
      agent.terminate
      exit
    end
  end

  begin
    focus = focus?
    definition.start(focus: focus)
    started = true
    if focus
      Log.info { "Host-side GRML REPL started in session 'grml'." }
    else
      Log.info { "Host-side GRML REPL started in session 'grml'; switch to it with: tmux switch-client -t grml" }
    end
    definition.serve
  ensure
    definition.stop if started
  end
end
