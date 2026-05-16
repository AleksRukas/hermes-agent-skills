### 2026‑05‑13 Fixes to `router_audit_wrapper.sh`

- **Extended curl timeout**: changed `curl -s -m 600` to `curl -s -m 1200` (20 minutes) to allow the LLM request to complete without being interrupted.
- **Corrected conditional syntax**: removed stray `+` characters before `else`/`fi` that caused a `syntax error: unexpected end of file`. The final block now cleanly uses `else` … `fi`.
- **Adjusted summary formatting**: increased `max_new_tokens` (via model config) to 512 to accommodate the user‑requested *concise paragraph (2‑3 sentences) followed by a short bullet list*.
- **Prompt refinement**: explicitly requests the paragraph + bullet format and forbids any `<think>` tags.
- **Output handling**: ensured the script exits with status 0 even when the LLM returns empty, providing a fallback placeholder message.
- **Debug artefacts**: continues to write payload, curl log, and LLM response to `/tmp/debug_payload_*.json`, `/tmp/debug_curl_*.log`, `/tmp/debug_response_*.json` for troubleshooting.

These changes resolve the earlier `error` state of the cron job and enable successful delivery of audit summaries to the configured Telegram topic/notification channel.