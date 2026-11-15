def build_definition(agent : T) : TmuxREPL::Definition forall T
  TmuxREPL.define("grml") do |repl|
    repl.on_command("ocr") do |context, arguments|
      raise ArgumentError.new("Usage: ocr") unless arguments.empty?
      result = agent.interaction.latest_ocr
      if error = result.error
        raise "OCR failed for frame #{result.timestamp}: #{error}"
      end
      result.text.strip.empty? ? context.puts("(no text recognized)") : context.write(result.text)
    end

    repl.on_command("guest_exec") do |context, arguments|
      raise ArgumentError.new("Usage: guest_exec <shell command>") if arguments.empty?

      command = arguments.join(" ")
      result = agent.interaction.execute(command, 2.minutes)
      context.write(result.stdout) unless result.stdout.empty?
      context.write(result.stderr) unless result.stderr.empty?
      context.puts("Guest command exited with status #{result.exit_code}") unless result.success?
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

    repl.on_command("create_ext4_disk") do |context, arguments|
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
  end
end
