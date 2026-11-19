private def disk_size_multiplier(unit : String?) : Int64
  case unit
  when "K" then 1024_i64
  when "M" then 1_048_576_i64
  when "G" then 1_073_741_824_i64
  when "T" then 1_099_511_627_776_i64
  when "P" then 1_125_899_906_842_624_i64
  else        1_i64
  end
end
