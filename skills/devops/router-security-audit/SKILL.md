---
name: router-security-audit
description: "Class‑level guide for scheduling a nightly security audit of an AsusWRT‑Merlin router using a forced‑command SSH script, optional local LLM parsing, and Hermes cron jobs."
---

# Router Security Audit (Hermes) – Class Level Skill

## When to use

## User Preferences (embedded)

- Summaries must be a concise paragraph (2‑3 sentences) **followed by** a short bullet list of key findings.
- The LLM prompt should explicitly forbid any internal thinking tags (`<think>`).
- Use `max_new_tokens` around 512‑1024 to allow the required detail while staying within model limits.
- Delivery of the cron job should be set to `origin` (this DM) to avoid group spam.


- You need a **recurring security audit** of an Asus RT‑AC86U (or any AsusWRT‑Merlin router). 
- The router is provisioned with a **forced‑command SSH key** that runs a custom audit script (e.g. `/jffs/scripts/hermes-audit.sh`).
- Optional: you want to **summarize logs with a local LLM** (Ollama, vLLM, llama.cpp, etc.) before delivering the report.

## Trigger conditions (example)

*User‑specific preferences (2026‑05‑13)
- Use a **concise paragraph (2‑3 sentences) followed by a short bullet list** for the LLM summary.
- Increase `max_new_tokens` to **1024** to allow richer output.
- Capture up to **800 bytes** of router log (still well within typical model context limits).
- Prompt explicitly forbids `<think>` tags and requests the exact format.
- Extraction script strips any `<think>` blocks and falls back to a placeholder if the LLM returns empty.
- Debug payload and response are saved to `/tmp/debug_payload.json` and `/tmp/debug_response.json` for troubleshooting.*
- The user now wants a **concise paragraph (2‑3 sentences) followed by a short bullet list** instead of a single‑sentence summary.
- Increase `max_new_tokens` to **512** (still well below the model’s context window) to allow the extra detail.
- Prompt should explicitly request the format and forbid any `<think>` tags.
- Extraction must strip any `<think>` blocks and fallback to a placeholder if the LLM returns empty.
- The wrapper script should write the raw payload and response to `/tmp/debug_payload.json` and `/tmp/debug_response.json` for troubleshooting.

```text
/cron create router‑audit --schedule "0 22 * * *" --model /model_dir --provider custom \
    --prompt "$(~/.hermes/scripts/router_audit_wrapper.sh)" \
    --deliver origin
```
```text
/cron create router‑audit --schedule "0 22 * * *" --model local-llm --provider local --prompt "{{SCRIPT_OUTPUT}}" --deliver origin
```
- `router‑audit` – any cron job whose name contains `router-audit` will use this skill.
- `--schedule` – daily at 06:00 SGT → `0 22 * * *` (UTC).
- `--model`/`--provider` – must point to a *local* LLM (see **Local LLM Setup** below).
- `--prompt` – the wrapper script injects the raw audit output into `{{SCRIPT_OUTPUT}}`.

## Step‑by‑step procedure
1. **Prepare the router script**
   - Upload `/jffs/scripts/hermes-audit.sh` (the version in `scripts/hermes-audit.sh`).
   - Ensure it is **executable**: `chmod +x /jffs/scripts/hermes-audit.sh`.
   - Verify the forced‑command line in `authorized_keys` points to the script.
2. **Validate required router tools**
   - The script expects `nvram`, `netstat`, `iptables`, `free`, and `date`. On busy‑box based routers `date -d` is unavailable; the script now falls back to a no‑filter approach and documents this in `references/busybox-date.md`.
3. **Set up a local LLM (if desired)**
   - Install Ollama (`apt install -y ollama`) or run a Docker image (`docker run -d -p 11434:11434 ollama/ollama`).
   - Pull a lightweight model (e.g. `ollama pull llama3:8b`).
   - Verify the endpoint works: `curl -s http://localhost:11434/api/generate -d '{"model":"llama3:8b","prompt":"Summarize logs:"}'`.
4. **Create the wrapper script** (`scripts/router_audit_wrapper.sh`)
   - SSH to the router using the pre‑loaded key (`~/.ssh/router_key`).
   - Run `hermes-audit.sh full_audit` and **capture the full log** without size cap.
   - **Filter the log to the most recent 24 hours** before embedding (see `references/log-24h-filtering.md`).
   - Build a **chat‑completion payload** via Python `json.dumps`; **do not set `max_tokens`** so the model can use its full context window.
   - Prompt explicitly requests a concise paragraph (2‑3 sentences) followed by a bullet list and forbids `<think>` tags.
   - Send the payload to the **vLLM chat endpoint** (`/v1/chat/completions`).
   - Extract the summary from either `choices[0].message.content` **or** `choices[0].reasoning` (Qwen‑AWQ places the answer in `reasoning`).
   - Echo the final summary; the script exits 0 even when the LLM returns nothing (fallback message printed).
5. **Register the Hermes cron job**
   ```bash
   hermes cron create router-audit \
       --schedule "0 22 * * *" \
       --model /model_dir \
       --provider custom \
       --prompt "$(~/.hermes/scripts/router_audit_wrapper.sh)" \
       --deliver origin
   ```
   - `--model /model_dir` points to the Qwen 3.6‑35B‑A3B‑AWQ model served by vLLM.
   - Use `--yolo` if you want to skip command‑approval prompts for the wrapper.
6. **Verify**
   - Run `hermes cron run <job_id>` manually to see the report.
   - Ensure the report arrives only in this DM.

## Pitfalls & Work‑arounds

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Argument list too long` from `curl -d "$PAYLOAD"` | Large JSON payload exceeding OS argument limits | Stream payload via stdin (`printf "%s" "$PAYLOAD" | curl … -d @-`) – see `references/wrapper-script-fixes.md` |
| Large audit logs cause LLM timeout or truncation | Model context window exceeded | **Filter logs to the last 24 hours** (see `references/log-24h-filtering.md`) and avoid explicit token caps. |
| `JSONDecodeError: Expecting value` or empty response from LLM | LLM returned empty or malformed JSON (often due to payload size, timeout, or unescaped characters) | Build the JSON payload via Python `json.dumps` to guarantee proper escaping (see `references/wrapper-script-fixes.md`). After the curl call, check if response is empty; if so, set `summary="[router_audit] No summary produced – LLM returned empty response."` and continue gracefully so cron exits 0. |
| Empty audit output from router | Logging disabled or wrong command | Enable syslog or switch to `hermes-audit.sh full_audit` – see `references/empty-audit-output.md` |
| LLM service unreachable (non‑200 HTTP) | Health‑check POST returned error (e.g., 405, 400) | Perform a lightweight POST with empty JSON before sending the real payload; if status ≠ 200, fall back to raw‑log excerpt. See `references/llm-healthcheck.md`. |
| ... (other rows unchanged) ... |

1. **Prepare the router script**
   - Upload `/jffs/scripts/hermes-audit.sh` (the version in `scripts/hermes-audit.sh`).
   - Ensure it is **executable**: `chmod +x /jffs/scripts/hermes-audit.sh`.
   - Verify the forced‑command line in `authorized_keys` points to the script.
2. **Validate required router tools**
   - The script expects `nvram`, `netstat`, `iptables`, `free`, and `date`. On busy‑box based routers `date -d` is unavailable; the script now falls back to a no‑filter approach and documents this in `references/busybox-date.md`.
3. **Set up a local LLM (if desired)**
   - Install Ollama (`apt install -y ollama`) or run a Docker image (`docker run -d -p 11434:11434 ollama/ollama`).
   - Pull a lightweight model (e.g. `ollama pull llama3:8b`).
   - Verify the endpoint works: `curl -s http://localhost:11434/api/generate -d '{"model":"llama3:8b","prompt":"Summarize logs:"}'`.
4. **Create the wrapper script** (`scripts/router_audit_wrapper.sh`)
   - SSH to the router using the pre‑loaded key (`~/.ssh/router_key`).
   - Run `hermes-audit.sh full_audit` and **capture only the first ~200 bytes** (safe for most LLM context windows).
   - Build a **chat‑completion payload** with a system instruction that forces a one‑sentence plain‑text summary. Example Python snippet is in `references/wrapper-script-fixes.md`.
   - Send the payload to the **vLLM chat endpoint** (`/v1/chat/completions`).
   - Extract the summary from either `choices[0].message.content` **or** `choices[0].message.reasoning` (Qwen‑AWQ places the answer in `reasoning`).
   - Echo the final summary; the script exits 0 even when the LLM returns nothing (fallback message printed).
5. **Register the Hermes cron job**
   ```bash
   hermes cron create router-audit \
       --schedule "0 22 * * *" \
       --model /model_dir \
       --provider custom \
       --prompt "$(~/.hermes/scripts/router_audit_wrapper.sh)" \
       --deliver origin
   ```
   - `--model /model_dir` points to the Qwen 3.6‑35B‑A3B‑AWQ model served by vLLM.
   - Use `--yolo` if you want to skip command‑approval prompts for the wrapper.
6. **Verify**
   - Run `hermes cron run <job_id>` manually to see the report.
   - Ensure the report arrives only in this DM.

## Pitfalls & Work‑arounds

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Argument list too long` from `curl -d "$PAYLOAD"` | Large JSON payload exceeding OS argument limits | Stream payload via stdin (`printf "%s" "$PAYLOAD" | curl … -d @-`) – see `references/wrapper-script-fixes.md` |
| Large audit logs cause LLM timeout or truncation | Model context window exceeded | Truncate log before embedding (`$(head -c 2000 "$LOG_FILE")`). Adjust size per model. |
| `JSONDecodeError: Expecting value` or empty response from LLM | LLM returned empty or malformed JSON (often due to payload size, timeout, or unescaped characters) | • Ensure payload size is limited (truncate log to ≤2000 bytes before sending). • Build JSON via Python `json.dumps` to guarantee proper escaping (see `references/wrapper-script-fixes.md`). • After the curl call, check if response is empty; if so, set `summary="[router_audit] No summary produced – LLM returned empty response."` and continue gracefully so cron exits 0. |
| Empty audit output from router | Logging disabled or wrong command | Enable syslog or switch to `hermes-audit.sh full_audit` – see `references/empty-audit-output.md` |
| LLM service unreachable (non‑200 HTTP) | Health‑check POST returned error (e.g., 405, 400) | Perform a lightweight POST with empty JSON before sending the real payload; if status ≠ 200, fall back to raw‑log excerpt. See `references/llm-healthcheck.md`. |
| ... (other rows unchanged) ... |

---

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Argument list too long` from `curl -d "$PAYLOAD"` | Large JSON payload exceeding OS argument limits | Stream payload via stdin (`printf "%s" "$PAYLOAD" | curl … -d @-`) – see `references/wrapper-script-fixes.md` |
| Large audit logs cause LLM timeout or truncation | Model context window exceeded | Truncate log before embedding (`$(head -c 2000 "$LOG_FILE")`). Adjust size per model. |
| `JSONDecodeError: Expecting value` or empty response from LLM | LLM returned empty or malformed JSON (often due to payload size, timeout, or unescaped characters) | • Ensure payload size is limited (truncate log to ≤2000 bytes before sending). • Build JSON via Python `json.dumps` to guarantee proper escaping (see `references/wrapper-script-fixes.md`). • After the curl call, check if response is empty; if so, set `summary="[router_audit] No summary produced – LLM returned empty response."` and continue gracefully so cron exits 0. |
| Empty audit output from router | Logging disabled or wrong command | Enable syslog or switch to `hermes-audit.sh full_audit` – see `references/empty-audit-output.md` |
| SSH connection times out when running `full_audit` | `full_audit` produces large output exceeding default 60 s limit | Use a shorter timeout (`-o ConnectTimeout=30`) and stream only the needed bytes: `ssh -i ~/.ssh/router_key -p SSH_PORT SSH_USER@ROUTER_IP "full_audit | head -c 2000"`.
| ... (other rows unchanged) ... |


| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Argument list too long` from `curl -d "$PAYLOAD"` | Large JSON payload exceeding OS argument limits | Stream payload via stdin (`printf "%s" "$PAYLOAD" | curl … -d @-`) – see `references/wrapper-script-fixes.md` |
| Large audit logs cause LLM timeout or truncation | Model context window exceeded | Truncate log before embedding (`$(head -c 20000 "$LOG_FILE")`). Adjust size per model. |
| `JSONDecodeError: Expecting value` or empty response from LLM | LLM returned empty or malformed JSON (often due to payload size, timeout, or unescaped characters) | • Ensure payload size is limited (truncate log to ≤2000 bytes before sending). • Build JSON via Python `json.dumps` to guarantee proper escaping (see `references/wrapper-script-fixes.md`). • After the curl call, check if response is empty; if so, set `summary="[router_audit] No summary produced – LLM returned empty response."` and continue gracefully so cron exits 0. |
| Empty audit output from router | Logging disabled or wrong command | Enable syslog or switch to `hermes-audit.sh full_audit` – see `references/empty-audit-output.md` |
| ... (other rows unchanged) ... |

---
| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `sh: ~/.hermes/scripts/router_audit_wrapper.sh: No such file or directory` | Cron job points to wrong script directory (`~/.hermes/scripts` instead of `~/.hermes/scripts`) | Update the cron definition to use the correct path (`~/.hermes/scripts/router_audit_wrapper.sh`) or place a symlink in the expected location. |
| ... (other rows unchanged) ...
| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `sh -n` reports a syntax error in `hermes-audit.sh` around the `tail_24h` function | BusyBox `date -d` not supported | The script now sets `limit=0` and skips time filtering (see `references/busybox-date.md`). |
| `netstat` or `iptables` commands missing on the router | Merlin build stripped those binaries | The script already prints a friendly fallback message; consider installing the missing utilities via Entware. |
| Cron job fails with `RuntimeError: No LLM provider configured` | Cron jobs don’t inherit the interactive session’s provider | Explicitly set `--model` and `--provider` to a local LLM when creating the job. |
| Report not delivered to this DM | `--deliver` omitted or set to a group | Use `--deliver origin` (or `deliver: "telegram:113272292"` if you prefer an explicit chat ID). |
| LLM takes >30 s and the cron job times out | Large model or CPU contention | Use a smaller model for scheduled jobs, or pre‑compute the summary and cache it (see **Pre‑compute pattern**). |
| Wrapper script fails to parse LLM JSON ("Invalid control character") | Payload built with raw `printf` and unescaped data | Build the JSON payload via Python (`json.dumps`) and export `SANITIZED_LOG` before constructing the payload (see `references/wrapper-script-fixes.md`). |
| Shell expands `!` in password strings, truncating them | Bash/BusyBox history expansion when using double quotes | Quote passwords with single quotes or escape the exclamation mark (`\!`). |
| Empty audit output from router (no log data) | Audit script missing, not executable, or wrong path in SSH command | Verify the script exists (`ls -l /jffs/scripts/hermes-audit.sh`), is executable (`chmod +x`), ensure the wrapper uses a **relative path** (e.g., `router_audit_wrapper.sh`) so Hermes can locate it, and consult `references/empty-audit-output.md` for additional troubleshooting. |

## References (included in the skill)

**Added after recent fix**
- The wrapper script now sanitizes log output, exports `SANITIZED_LOG`, builds the JSON payload via Python to avoid control‑character errors, and parses the LLM response with a compact one‑liner. See `references/wrapper-script-fixes.md` for the exact diff.

- `references/busybox-date.md` – why `date -d` fails on AsusWRT‑Merlin and the simple workaround used.
- `templates/hermes‑audit‑script-template.sh` – a clean template for future router audit scripts.
- `scripts/router_audit_wrapper.sh` – the exact wrapper the cron job invokes.

---

**Maintenance**

## Recent fixes (2026‑05‑12)
- Added static “Audit Log:” preamble to the LLM prompt to avoid empty responses.
- Reduced `max_tokens` to 256 for concise summaries.
- Documented vLLM payload‑size limit; wrapper now truncates log to ≤2 KB and streams JSON via stdin.
- Updated wrapper script to exit with status 0 on empty LLM output.

- When the router firmware updates and new log locations appear, edit the `hermes-audit.sh` template.
- When a better local LLM becomes available, update the `--model` example in the cron‑job command.
- Add new pitfalls as they are discovered (e.g., changes in `nvram` keys).

## Recent fixes (2026‑05‑13)
- Updated wrapper script to use the **chat completions** endpoint (`/v1/chat/completions`) matching the model’s API.
- Added robust JSON extraction handling both `choices[0].message.content` and legacy `choices[0].text`/`reasoning` fields.
- Switched payload construction to a **Python `json.dumps`** approach, eliminating control‑character issues.
- Implemented `<think>` block stripping and fallback placeholder when the LLM returns empty.
- Saved raw payload, curl verbose log, and LLM response to `/tmp/debug_payload.json`, `/tmp/debug_curl.log`, and `/tmp/debug_response.json` for easier debugging.
- Adjusted `max_new_tokens` to 512 to accommodate the requested 2‑3‑sentence paragraph plus bullet list.
- Updated the LLM prompt to explicitly request the concise paragraph + bullet list format and to forbid any internal thinking tags.
- Added a new reference `references/router_audit_wrapper_fix_20260513.md` documenting these changes.
---
