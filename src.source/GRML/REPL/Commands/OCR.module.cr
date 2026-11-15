NAME = "ocr"

def self.register(repl : TmuxREPL::Definition, agent : T) : Nil forall T
  repl.on_command(NAME) do |context, arguments|
    raise ArgumentError.new("Usage: ocr") unless arguments.empty?

    result = agent.interaction.latest_ocr
    if error = result.error
      raise "OCR failed for frame #{result.timestamp}: #{error}"
    end

    result.text.strip.empty? ? context.puts("(no text recognized)") : context.write(result.text)
  end
  nil
end
