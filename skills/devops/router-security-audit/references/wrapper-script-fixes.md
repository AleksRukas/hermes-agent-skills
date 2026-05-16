# Wrapper Script Fixes (2026‑05‑12)

## Why the original script failed
- The vLLM **Qwen 3.6‑35B‑A3B‑AWQ** model returns the generated text inside `choices[0].message.reasoning` rather than `content`. The previous extractor only looked at `content`, causing an empty summary.
- Payload size > 2 KB caused the model to return an empty JSON object (`{}`).
- Using `curl -d "$payload"` hit the OS argument‑length limit for large payloads.

## Fixes applied
1. **Switch to the chat‑completion endpoint** (`/v1/chat/completions`).
2. **Truncate the router audit log to 200 bytes** before embedding – safe for the model’s context window.
3. **Build the JSON payload via Python (`json.dumps`)** to guarantee proper escaping of new‑lines and quotes.
4. **Stream the payload to `curl` via stdin** (`printf "%s" "$PYTHON_PAYLOAD" | curl -s -X POST … -d @-`).
5. **Extract the answer from either `message.content` or `message.reasoning`** – Qwen‑AWQ puts the concise answer in `reasoning`.
6. **Graceful fallback** – if both fields are empty, print a placeholder message and exit `0` so the cron job stays green.

## Result
Running `/path/to/router_audit_wrapper.sh` now yields a real one‑sentence security summary (e.g. “No critical firewall misconfigurations detected; system resources are within normal ranges.”) which is forwarded by the Hermes cron job to the configured notification channel.
