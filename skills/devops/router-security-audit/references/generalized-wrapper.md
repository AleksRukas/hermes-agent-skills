# Generalized Router Audit Wrapper

The `router_audit_wrapper.sh` script has been updated to use **environment‑variable defaults** instead of hard‑coded values, making it reusable across different deployments and suitable for public sharing on GitHub.

## Environment variables (with defaults)
```
ROUTER_IP   = ${ROUTER_IP}
SSH_PORT    = ${SSH_PORT}
SSH_USER    = ${SSH_USER}
SSH_KEY     = ${SSH_KEY:-~/.ssh/router_key
REMOTE_CMD  = ${REMOTE_CMD:-full_audit}
LLM_URL     = ${LLM_URL:}
MODEL_PATH  = ${MODEL_PATH:}
```
Export any of these before invoking the script, or place them in a `.env` file and source it.

## Why this matters
- **Portability** – The same script works for any router IP, SSH port, or user without editing the file.
- **Security** – Credentials are injected via environment rather than being baked into source control.
- **GitHub‑ready** – Others can clone the repository and simply set their own variables.

For a full example of how the script is used in a Hermes cron job, see the skill documentation under **Step‑by‑step procedure**.
