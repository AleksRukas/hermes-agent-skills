# vLLM Endpoint Quirks (As of 2026‑05‑13)

- The **chat completions** endpoint (`/v1/chat/completions`) on the Qwen 3.6‑35B‑AWQ model frequently returns a *504 Gateway Timeout* when the payload exceeds ~1 KB or when the model needs >30 s to generate text. This is observed on our local vLLM deployment behind the router.
- The **standard completions** endpoint (`/v1/completions`) is more stable for the same model and respects the `max_new_tokens` limit without timing out as aggressively.
- When using the chat endpoint, ensure `stream` is **false** and the request body is **compact** (avoid large `system` messages). Prefer sending the full prompt in the `prompt` field rather than as `messages`.
- For debugging, capture both the request payload and the raw response:
  ```bash
  printf "%s" "$PYTHON_PAYLOAD" > /tmp/debug_payload.json
  curl -s -X POST -H "Content-Type: application/json" -d @/tmp/debug_payload.json \
       http://127.0.0.1:9000/v1/completions > /tmp/debug_response.json
  ```
- If the response is empty or malformed, fall back to a static placeholder (`"Router audit completed – no summary could be generated."`).
- Future models (e.g., Llama‑3.1‑8B‑GGUF) may behave differently; revisit this file after a model upgrade.
