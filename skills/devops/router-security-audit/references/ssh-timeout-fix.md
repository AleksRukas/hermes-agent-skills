# SSH Timeout & Log Size Mitigation

When invoking `full_audit` on an AsusWRT‑Merlin router the command can generate a **very large** output that exceeds the default SSH channel timeout (usually 60 seconds). This leads to the wrapper script aborting before any log data is saved, which then causes the downstream LLM request to fail.

## Recommended pattern
```bash
ssh -i ~/.ssh/id_rsa -p 22 \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=5 \
    admin@ROUTER_IP \
    "full_audit | head -c 2000"
```
- **`ConnectTimeout=30`** – limits the time spent establishing the connection.
- **`ServerAliveInterval=5`** – keeps the session alive on long‑running commands.
- **`head -c 2000`** – streams only the first *N* bytes (adjust size to fit your LLM’s context window).

You can store the output directly to a temporary file:
```bash
LOG_FILE=$(mktemp)
ssh … "full_audit | head -c $MAX_BYTES" > "$LOG_FILE"
```
Replace `$MAX_BYTES` with a safe value (e.g., `2000` for an 8 KB‑ish payload after JSON wrapping).

## Why this works
- **Avoids OS argument‑length limits**: The payload stays small enough for `curl`’s `-d @-` streaming.
- **Prevents LLM timeouts**: The sent log fits comfortably within most local model context windows (2‑4 KB of raw log is typical).
- **Keeps cron jobs stable**: No stderr is emitted and the script exits with status 0 even if the router returns a truncated log.

### Integration into `router_audit_wrapper.sh`
Replace the original SSH command with the snippet above, adjusting `MAX_BYTES` as needed. After capturing the log, continue with the existing Python JSON builder to ensure proper escaping.
