class ProfileCompositionSpecInteraction
  def execute_streaming(command : String, timeout : Time::Span = 30.seconds,
                        &block : Symbol, String ->) : QEMU::CommandResult
    QEMU::CommandResult.new(0, "", "")
  end
end
