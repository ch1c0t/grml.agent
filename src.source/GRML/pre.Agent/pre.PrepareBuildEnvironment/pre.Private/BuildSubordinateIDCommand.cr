private def build_subordinate_id_command : String
  <<-PYTHON
    python3 - <<'PY'
    from pathlib import Path
    username, count = "#{GRML_LIVE_BUILDER}", 65536

    def ensure_range(filename):
        path = Path(filename)
        path.touch(exist_ok=True)
        entries = []
        for line in path.read_text(encoding="utf-8").splitlines():
            fields = line.split(":")
            if len(fields) == 3:
                try:
                    entries.append((fields[0], int(fields[1]), int(fields[2])))
                except ValueError:
                    pass
        if any(name == username and size >= count for name, _, size in entries):
            return
        start = 100000
        while True:
            ends = [first + size for _, first, size in entries
                    if start < first + size and start + count > first]
            if not ends:
                break
            start = max(ends)
        with path.open("a", encoding="utf-8") as stream:
            stream.write(f"{username}:{start}:{count}\\n")

    ensure_range("/etc/subuid")
    ensure_range("/etc/subgid")
    PY
  PYTHON
end
