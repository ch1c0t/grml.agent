def run(agent : Agent) : Nil
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
