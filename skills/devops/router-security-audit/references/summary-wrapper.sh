#!/bin/sh
# ==============================================================================
# Generic Device Audit -> Local LLM Summariser Wrapper
# ==============================================================================
# This script retrieves a log from a remote device via SSH, sanitizes it,
# sends it to a local LLM (following OpenAI schema) for summarization,
# and saves the results.
# ==============================================================================

# ----------------------------------------------------------------------
# Configuration (Override these via environment variables or here)
# ----------------------------------------------------------------------
SSH_KEY="${SSH_KEY_PATH:-/path/to/your/key}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"
REMOTE_HOST="${REMOTE_HOST:-ROUTER_IP}"
REMOTE_CMD="${REMOTE_CMD:-full_audit}"

LLM_ENDPOINT="${LLM_ENDPOINT:-http://localhost:9000/v1}"
MODEL_NAME="${MODEL_NAME:-local-model}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/audit_logs}"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# ----------------------------------------------------------------------
# 1. Run the remote audit via SSH
# ----------------------------------------------------------------------
echo ">> Retrieving audit log..."
LOG=$(ssh -i "${SSH_KEY}" -p "${SSH_PORT}" "${SSH_USER}@${REMOTE_HOST}" "${REMOTE_CMD}" 2>&1)

# ----------------------------------------------------------------------
# 2. Send the raw log to the local LLM for a concise summary
# ----------------------------------------------------------------------
# Sanitize and truncate log (max 4 KB) before JSON encoding
LOG_TRUNC=$(printf '%s' "$LOG" | head -c 4096)
SANITIZED_LOG=$(printf '%s' "$LOG_TRUNC" | python3 - <<'PY'
import sys, re
log = sys.stdin.read()
print(re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', log))
PY
)
export SANITIZED_LOG

# Construct JSON payload
PAYLOAD=$(python3 - <<'PY'
import os, json

log = os.getenv('SANITIZED_LOG')
model = os.getenv('MODEL_NAME', 'local-model')

payload = {
    "model": model,
    "prompt": "Summarize the following device audit log and highlight any security concerns:\n\n" + log
}

print(json.dumps(payload))
PY
)

# Call the LLM endpoint
echo ">> Querying LLM..."
RESPONSE=$(curl -s -X POST "${LLM_ENDPOINT}/completions" -H "Content-Type: application/json" -d "$PAYLOAD")

# Extract the summary text
SUMMARY=$(printf '%s' "$RESPONSE" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("choices",[{}])[0].get("text","").strip())')

# ----------------------------------------------------------------------
# 3. Store full log + summary for later reference
# ----------------------------------------------------------------------
TS=$(date +%Y%m%d_%H%M%S)
OUTFILE="${OUTPUT_DIR}/audit_log_${TS}.txt"
printf "%s\n\n--- Summary ---\n%s\n" "$LOG" "$SUMMARY" > "$OUTFILE"
echo ">> Saved to: ${OUTFILE}"

# ----------------------------------------------------------------------
# 4. Print the summary – this stdout will be forwarded by the cron job
# ----------------------------------------------------------------------
printf "%s\n" "$SUMMARY"