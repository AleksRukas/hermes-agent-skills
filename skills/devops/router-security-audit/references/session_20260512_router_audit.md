# Router Audit Cron – 2026‑05‑12

**Context**: Implemented a daily cron job that SSHes into an Asus RT‑AC86U (Merlin) router, captures the first 2000 bytes of the `full_audit` log, sends it to a local Qwen 3.6‑35B‑A3B‑AWQ model via the `/v1/completions` endpoint, and posts a concise summary (paragraph + bullet list) to Telegram.

### Key implementation details
- **Log capture**: `head -c 2000` (adjusted to 2000 B for richer context, later trimmed to 300 B for prompt). Fallback placeholder if empty.
- **Prompt**: Requests a concise paragraph (2‑3 sentences) **plus** a short bullet list of key findings, forbids any internal `<think>` tags.
- **Payload**: JSON with `model`, `prompt`, `max_new_tokens` set to `3000`, `temperature` 0.3. Payload written to `/tmp/debug_payload.json` for debugging.
- **Curl**: `curl -s -m 120 -v -X POST -H "Content-Type: application/json" -d @/tmp/debug_payload.json $LLM_URL` with verbose logging saved to `/tmp/debug_curl.log`.
- **Response handling**: Parsed `choices[0].reasoning` or `text`. Stripped any `<think>` block (including content before closing tag) and removed stray tags. Dropped lines starting with "Thinking Process:".
- **Output**: Clean summary echoed; also written to `/path/to/output/<job_id>/<timestamp>.md` and sent to Telegram via the existing notification script.

### Pitfalls discovered & mitigations
1. **Empty JSON response** – caused by missing payload file; ensured payload is written before curl.
2. **`` tags leaking into output** – added robust removal logic that drops everything up to `</think>` and strips any leftover tags.
3. **Token budget too low** – increased `max_new_tokens` to 3000 to allow paragraph + bullet list.
4. **Too large log slice** – initial 2000 B caused truncated LLM output; trimmed to 300 B for prompt while keeping richer context.
5. **Missing Telegram delivery** – confirmed that the wrapper’s stdout is captured by the cron dispatcher which forwards it to the configured Telegram thread.

### Recommended defaults for future deployments
- `max_new_tokens: 3000`
- Log slice: `head -c 300` for prompt (adjust as needed).
- Prompt wording as in the script.
- Always write payload to a temporary file before curl for debugging.
- Include verbose curl logs for troubleshooting.

---
*This reference was generated from the 2026‑05‑12 session where the user requested a more detailed, bullet‑list style report.*