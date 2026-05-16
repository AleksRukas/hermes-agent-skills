# Output Formatting for LLM Summaries

When the wrapper script receives a response from the local vLLM (Qwen 3.6‑35B‑A3B‑AWQ), the model often returns a JSON payload where the actual summary is embedded in either:

- `choices[0].reasoning`
- `choices[0].text`

Additionally, the model may include a `<think>...</think>` block that contains internal reasoning text. For a **user‑readable** one‑sentence report (exactly what the cron job delivers to Telegram), follow these steps:

1. **Parse the JSON safely** – use Python's `json.loads` on the entire response string.
2. **Extract the answer**:
   ```python
   choice = data.get('choices', [{}])[0]
   summary = choice.get('reasoning') or choice.get('text') or ''
   ```
3. **Strip any `<think>` blocks** with a regular expression:
   ```python
   import re
   summary = re.sub(r'<think>.*?</think>', '', summary, flags=re.DOTALL)
   ```
4. **Trim whitespace** and ensure the result is a single line.
5. **Fallback** – if the resulting string is empty, output the placeholder message:
   ```bash
   echo "Router audit completed – no notable findings or summary could be generated."
   ```

The final output is then echoed by the wrapper script; Hermes cron forwards exactly that line to the configured Telegram DM.

**Why this matters**
- Guarantees the cron job never emits raw JSON or internal reasoning.
- Keeps the message concise (one sentence) for quick reading.
- Prevents `json.decoder.JSONDecodeError` by ensuring the payload is well‑formed before parsing.

Reference implementations can be found in `scripts/router_audit_wrapper.sh` where the extraction logic lives.
