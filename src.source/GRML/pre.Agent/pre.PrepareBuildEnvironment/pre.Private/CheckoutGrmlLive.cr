private def checkout_grml_live(ref : String, progress : Proc(String, Nil)? = nil) : String
  report_build_environment_stage(6, "Checking out grml-live source", progress) do
    checkout_grml_live_ref(ref, progress)
  end
end
