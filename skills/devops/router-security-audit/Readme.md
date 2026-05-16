# Router Security Audit (Hermes) – Markdown Overview

*Category:* **devops**
*Skill name:* `router-security-audit`

---

## 📄 Description

A class‑level guide for **automating a nightly security audit** of an Asus RT‑AC86U (or any AsusWRT‑Merlin) router.

- Uses a **forced‑command SSH key** that runs a custom audit script (`hermes-audit.sh`) on the router.
- Optionally pipes the raw audit log to a **local LLM** (Ollama, vLLM, etc.) to generate a concise summary.
- Schedules the whole flow with a **Hermes cron job** that delivers the formatted report **only to this DM** (no group spam).

The skill encodes user preferences for the report format (2‑3‑sentence paragraph + bullet list) and includes extensive pitfalls & work‑arounds.

---

## 🚀 When to Use

- You need a **recurring security check** (e.g., daily).
- You want the audit output **summarized by a local LLM** for easy reading.
- You prefer the report to be sent **directly to your private Telegram DM**.

---

## 🔧 Prerequisites

| Item | Details |
|------|----------|
| **Router script** | `hermes-audit.sh` uploaded to `/jffs/scripts/` and executable (`chmod +x`). |
| **Forced‑command SSH key** | Authorized key points to the audit script; key stored at `~/.ssh/router_ssh_key`. |
| **Router utilities** | `nvram`, `netstat`, `iptables`, `free`, `date` (fallback for busy‑box `date -d`). |
| **Local LLM (optional)** | Ollama (`apt install ollama`) **or** Docker `ollama/ollama`; pull a model (e.g., `llama3:8b`). |
| **Hermes cron** | `hermes` CLI available in your PATH. |
| **Network access** | SSH port `22` (or custom port) reachable from the Hermes container. |

---

## 🛠️ Step‑by‑step Procedure

1. **Upload & prepare the router audit script**
   ```bash
   scp hermes-audit.sh admin@<ROUTER_IP>:/jffs/scripts/
   ssh admin@<ROUTER_IP> "chmod +x /jffs/scripts/hermes-audit.sh"
   ```
   Verify the forced‑command line in `~/.ssh/authorized_keys` points to this script.

2. **(Optional) Install a local LLM**
   ```bash
   apt install -y ollama          # or start Docker container
   ollama pull llama3:8b
   curl -s http://localhost:11434/api/generate \
        -d '{"model":"llama3:8b","prompt":"Summarize logs:"}'
   ```

3. **Create the wrapper script** (`router_audit_wrapper.sh`)
   * SSH to the router using `~/.ssh/router_ssh_key`.
   * Run `hermes-audit.sh full_audit` and **capture ≤ 2 KB** of log (safe for model context windows).
   * Build a **JSON payload** via Python `json.dumps` (avoids control‑character errors).
   * Send payload to the LLM’s `/v1/chat/completions` endpoint, prompting for:
     - a concise 2‑3‑sentence paragraph,
     - a short bullet list of findings,
     - **no `think` tags**.

---

## 📦 Deliver the cron job

```bash
hermes cron create router-audit \
    --schedule "0 22 * * *" \   # 05:40 SGT = 22:40 UTC
    --model /model_dir \       # Example: Daily at 22:00 UTC
    --provider custom \        # local LLM provider (e.g., Ollama/vLLM)
    --prompt "$(~/.hermes/scripts/router_audit_wrapper.sh)" \
    --deliver origin            # send only to this DM
```

Run `hermes cron run <job-id>` once to verify the output lands in your private Telegram chat.

---

## ⚠️ Pitfalls & Work‑arounds (summary)

- **Argument list too long** – stream JSON via stdin (`printf "%s" "$PAYLOAD" | curl … -d @-`).
- **Large logs** – truncate to ≤ 2 KB before sending to the LLM.
- **JSONDecodeError** – always build payload with Python `json.dumps` and check for empty responses; fall back to a placeholder.
- **Busy‑box `date -d` missing** – the script now skips time filtering (see references).
- **SSH timeout** – use `-o ConnectTimeout=30` and `head -c 2000` to limit output size.
- **Cron delivery to wrong chat** – ensure `--deliver origin` (or explicitly `--deliver "telegram:<CHAT_ID>"`).

---

## 📚 References (included in the skill)

- `references/empty-audit-output.md`
- `references/ssh-timeout-fix.md`
- `references/wrapper-script-fixes.md`
- `references/output-formatting.md`
- `references/session_20260512_router_audit.md`
- `references/vllm-endpoint-quirks.md`
- `references/log-24h-filtering.md`
- `references/router_audit_wrapper_fix_20260513.md`

---

*End of How‑TO.md*