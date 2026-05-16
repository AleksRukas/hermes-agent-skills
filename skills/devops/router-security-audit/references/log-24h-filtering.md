# Log 24‑hour Filtering Reference

The router audit wrapper now limits the log sent to the LLM to entries from the most recent 24 hours. This is implemented in the Python payload‑building block:

```python
import datetime, re
cutoff = datetime.datetime.utcnow() - datetime.timedelta(hours=24)

def line_is_recent(line):
    # ISO timestamp (e.g., 2026-05-13 21:40:04)
    m = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
    if m:
        try:
            dt = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            return dt >= cutoff
        except Exception:
            pass
    # Syslog style (e.g., May 13 21:40:04)
    m2 = re.search(r"^(\w{3})\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2})", line)
    if m2:
        try:
            month_str, day_str, time_str = m2.group(1), m2.group(2), m2.group(3)
            dt = datetime.datetime.strptime(f"{month_str} {day_str} {time_str}", "%b %d %H:%M:%S")
            dt = dt.replace(year=datetime.datetime.utcnow().year)
            return dt >= cutoff
        except Exception:
            pass
    # Keep lines without recognizable timestamps – they may contain useful context.
    return True
```

**Why this matters**
- Keeps the payload well‑within typical LLM context windows (≈8 k‑token models).
- Prevents old, irrelevant events from diluting the summary.
- Works even when timestamps are missing; such lines are retained.

**Fallback**
If no timestamps are detected, the entire log is sent (the script already truncates to a reasonable size).

**Related skill sections**
- Updated **Step‑by‑step procedure** in the main skill to reference this file.
- The wrapper script imports this logic directly; no external file is needed at runtime.
