#!/usr/bin/env bash
# Router audit wrapper for Hermes cron
# SSH into Asus RT-AC86U (Merlin) router, capture raw logs, summarize via local vLLM, output summary.

# Configuration (override via environment variables if desired)
ROUTER_IP="${ROUTER_IP:-ROUTER_IP}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-admin}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
# Remote command to perform full audit
REMOTE_CMD="${REMOTE_CMD:-full_audit}"

# Local LLM endpoint (OpenAI-compatible, e.g., vLLM, Ollama)
LLM_URL="${LLM_URL:-http://127.0.0.1:9000/v1/chat/completions}"
MODEL_PATH="${MODEL_PATH:-local-model}"
TIMEZONE="${TIMEZONE:-UTC}"

# Capture raw logs from router (fallback to placeholder if empty)
RAW_LOG=$(timeout 600s ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER"@"$ROUTER_IP" "$REMOTE_CMD" 2>/dev/null || true)
if [[ -z "$RAW_LOG" ]]; then
  RAW_LOG="No logs available on router."
fi

# Store logs in a temporary file for easier handling
LOG_FILE="$(mktemp /tmp/router_audit_XXXX.log)"
DEBUG_PAYLOAD="$(mktemp /tmp/debug_payload_XXXX.json)"
DEBUG_RESPONSE="$(mktemp /tmp/debug_response_XXXX.json)"
DEBUG_CURL="$(mktemp /tmp/debug_curl_XXXX.log)"

# Clean up temporary files on exit
trap 'rm -f "$LOG_FILE" "$DEBUG_PAYLOAD" "$DEBUG_RESPONSE" "$DEBUG_CURL"' EXIT

echo "$RAW_LOG" > "$LOG_FILE"

export LOG_FILE
PYTHON_PAYLOAD=$(python3 - <<EOF
import os, json, pathlib, datetime, re
log_path = os.environ["LOG_FILE"]
log_content = pathlib.Path(log_path).read_text(errors='replace')
# Determine cutoff for last 24 hours (UTC)
cutoff = datetime.datetime.utcnow() - datetime.timedelta(hours=24)

def line_is_recent(line):
    # Try to find a timestamp like YYYY-MM-DD HH:MM:SS at start of line
    # Try ISO format first
    m = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", line)
    if m:
        try:
            dt = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            return dt >= cutoff
        except Exception:
            pass
    # Try syslog format e.g., 'May 13 21:40:04'
    m2 = re.search(r"^(\w{3})\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2})", line)
    if m2:
        try:
            month_str, day_str, time_str = m2.group(1), m2.group(2), m2.group(3)
            dt = datetime.datetime.strptime(f"{month_str} {day_str} {time_str}", "%b %d %H:%M:%S")
            # Assume current year
            dt = dt.replace(year=datetime.datetime.utcnow().year)
            return dt >= cutoff
        except Exception:
            pass
    # If no recognizable timestamp, keep the line
    return True

filtered_lines = [ln for ln in log_content.splitlines() if line_is_recent(ln)]
# Limit to first 500 lines to keep payload manageable
filtered_lines = filtered_lines[:500]
filtered_log = "\n".join(filtered_lines)
prompt = (
    "You are a Network Security auditor. Summarize the following audit log. Provide a concise paragraph (2‑3 sentences) followed by a short bullet list of key findings. Do NOT include any internal thinking tags (e.g., <think>). Return ONLY the summary text.\n\n"
    "Audit Log:\n" + filtered_log + "\n\nSummarize as described."
)
payload = {
    "model": "$MODEL_PATH",
    "messages": [{"role": "user", "content": prompt}],
    "temperature": 0.3,
}
print(json.dumps(payload))
EOF
)
# Debug: write payload
echo "$PYTHON_PAYLOAD" > "$DEBUG_PAYLOAD"
    # Send payload to LLM (600s timeout). Capture HTTP status code.
    LLM_RESPONSE=$(curl -s -m 1200 -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$PYTHON_PAYLOAD" "$LLM_URL")
    # Separate body and status
    HTTP_BODY=$(echo "$LLM_RESPONSE" | sed '$d')
    HTTP_STATUS=$(echo "$LLM_RESPONSE" | tail -n1)
    if [[ "$HTTP_STATUS" != "200" || -z "$HTTP_BODY" ]]; then
      echo "LLM service unreachable or error (status $HTTP_STATUS). Returning raw log excerpt." > "$DEBUG_RESPONSE"
      head -n 20 "$LOG_FILE"
      exit 0
    fi
    # Save raw response for debugging
    echo "$HTTP_BODY" > "$DEBUG_RESPONSE"
# Extract the generated text (compatible with OpenAI chat, completions, and vLLM responses)
export DEBUG_RESPONSE
SUMMARY=$(python3 - <<'PY'
import os, json, re, sys
# Load response JSON
try:
    with open(os.environ['DEBUG_RESPONSE']) as f:
        data = json.load(f)
except Exception as e:
    print(f"Error parsing LLM response: {e}")
    sys.exit(1)

text = ''
if isinstance(data, dict):
    # OpenAI chat style (choices[].message.content)
    if 'choices' in data and data['choices']:
        first = data['choices'][0]
        if isinstance(first, dict):
            # chat completion
            msg = first.get('message')
            if isinstance(msg, dict):
                text = msg.get('content', '')
            # fallback to older fields
            if not text:
                text = first.get('text') or first.get('reasoning', '')
    # Legacy completions may put the text directly under 'text'
    if not text and 'text' in data:
        text = data['text']

# Strip any <think> blocks if present
if '<think>' in text:
    # keep content after the closing tag if it exists
    end = text.find('</think>')
    if end != -1:
        text = text[end + len('</think>'):]
    else:
        text = text.split('<think>', 1)[0]
# Remove stray tags
text = re.sub(r'<[/]?think>', '', text)
# Build clean summary lines
lines = []
for ln in text.splitlines():
    s = ln.strip()
    if not s:
        continue
    if s.lower().startswith('thinking process'):
        continue
    lines.append(s)
summary = "\n".join(lines)
print(summary.strip())
PY
)

# Output the summary – Hermes cron will deliver this to the configured Telegram target
TIMESTAMP=$(TZ="$TIMEZONE" date '+%Y-%m-%d %H:%M:%S %Z')
if [[ -z "$SUMMARY" ]]; then
  echo "[$TIMESTAMP] Router audit completed – no notable findings or summary could be generated."
   # Provide a short raw‑log excerpt as a safety net
   head -n 20 "$LOG_FILE"
   exit 0
else
  echo "[$TIMESTAMP] $SUMMARY"
  exit 0
fi
