#!/usr/bin/env sh
# Creates seed virtual keys in LiteLLM for reproducible test/dev setup.
# Idempotent — skips keys that already exist (LiteLLM returns 400 on duplicate key value).
# Usage: ./scripts/seed-keys.sh
# Requires: LiteLLM running and LITELLM_MASTER_KEY in .env

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"

# Load .env
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  echo "error: LITELLM_MASTER_KEY not set in .env" >&2
  exit 1
fi

# Wait for LiteLLM to be ready
echo "waiting for LiteLLM at $LITELLM_URL ..."
MAX=30
i=0
until curl -sf "$LITELLM_URL/health/liveliness" > /dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge "$MAX" ]; then
    echo "error: LiteLLM not ready after ${MAX}s" >&2
    exit 1
  fi
  sleep 1
done
echo "LiteLLM ready"
echo ""

# Create a key. Skips silently if key value already exists.
create_key() {
  _alias="$1"
  _key="$2"
  _body="$3"

  status=$(curl -s -o /tmp/litellm_key_resp.json -w "%{http_code}" \
    -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$_body")

  if [ "$status" = "200" ]; then
    echo "created  $_alias ($_key)"
  elif [ "$status" = "400" ]; then
    echo "exists   $_alias ($_key)"
  else
    echo "failed   $_alias ($_key) — HTTP $status"
    cat /tmp/litellm_key_resp.json
    echo ""
  fi
}

# --- Seed keys ---

create_key "claude-code" "sk-claude-code" "$(cat <<JSON
{
  "key": "sk-claude-code",
  "key_alias": "claude-code",
  "duration": null
}
JSON
)"

create_key "test-logging-enabled" "sk-test-logging-on" "$(cat <<JSON
{
  "key": "sk-test-logging-on",
  "key_alias": "test-logging-enabled",
  "duration": null
}
JSON
)"

create_key "test-logging-disabled" "sk-test-logging-off" "$(cat <<JSON
{
  "key": "sk-test-logging-off",
  "key_alias": "test-logging-disabled",
  "duration": null,
  "metadata": {
    "turn_off_message_logging": true
  }
}
JSON
)"

# Add more seed keys here following the same pattern.

echo ""
echo "done"
