private def raise_ext4_disk_provisioning_error(result, path)
  details = [result.stdout.strip, result.stderr.strip].reject { |part| part.empty? }.join("\n")
  message = "Could not provision persistent ext4 build workspace (exit=#{result.exit_code})"
  message += ":\n#{details}" unless details.empty?
  raise "#{message}. Disk image is retained at #{path} for recovery."
end
