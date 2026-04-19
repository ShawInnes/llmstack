#!/usr/bin/env sh
# Generates litellm-models.yaml and litellm-search.yaml in config/ based on
# API keys in the environment. litellm-config.yaml (main) is static.
# Sources .env from project root if present.
# Usage: ./scripts/generate-litellm-config.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

ENV_FILE="$PROJECT_ROOT/.env"
touch "$ENV_FILE"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# Write or update a key=value in .env (does not overwrite existing keys)
set_env_var() {
  _key="$1" _val="$2"
  if grep -q "^${_key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i.bak "s|^${_key}=.*|${_key}=${_val}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    echo "${_key}=${_val}" >> "$ENV_FILE"
  fi
}

# --- secrets ---

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
  set_env_var LITELLM_MASTER_KEY "$LITELLM_MASTER_KEY"
  echo "generated LITELLM_MASTER_KEY"
fi

if [ -z "${LITELLM_SALT_KEY:-}" ]; then
  LITELLM_SALT_KEY="$(openssl rand -hex 32)"
  set_env_var LITELLM_SALT_KEY "$LITELLM_SALT_KEY"
  echo "generated LITELLM_SALT_KEY"
fi

# Langfuse API key pair — generate once, shared by LiteLLM callback and Langfuse init project
if [ -z "${LANGFUSE_PUBLIC_KEY:-}" ]; then
  LANGFUSE_PUBLIC_KEY="lf_pk_$(openssl rand -hex 20)"
  LANGFUSE_SECRET_KEY="lf_sk_$(openssl rand -hex 20)"
  set_env_var LANGFUSE_PUBLIC_KEY "$LANGFUSE_PUBLIC_KEY"
  set_env_var LANGFUSE_SECRET_KEY "$LANGFUSE_SECRET_KEY"
  echo "generated LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY"
fi

# Init project keys mirror the API key pair so LiteLLM can connect on first boot
set_env_var LANGFUSE_PUBLIC_KEY "$LANGFUSE_PUBLIC_KEY"
set_env_var LANGFUSE_SECRET_KEY "$LANGFUSE_SECRET_KEY"

echo ""
echo "  LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY"
echo "  LANGFUSE_PUBLIC_KEY=$LANGFUSE_PUBLIC_KEY"
echo ""

# --- models ---

MODELS="$CONFIG_DIR/litellm-models.yaml"
: > "$MODELS"  # truncate

HAS_MODEL=0
for key in OPENAI_API_KEY ANTHROPIC_API_KEY PERPLEXITYAI_API_KEY CODESTRAL_API_KEY COHERE_API_KEY; do
  eval "val=\${${key}:-}"
  [ -n "$val" ] && HAS_MODEL=1 && break
done

if [ "$HAS_MODEL" = "1" ]; then
  echo "model_list:" >> "$MODELS"

  [ -n "${OPENAI_API_KEY:-}" ] && cat >> "$MODELS" << 'YAML'
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
YAML

  [ -n "${ANTHROPIC_API_KEY:-}" ] && cat >> "$MODELS" << 'YAML'
  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: os.environ/ANTHROPIC_API_KEY
      cache_control_injection_points:
        - location: message
          role: system      
  - model_name: claude-sonnet-4-6
    litellm_params:
      model: anthropic/claude-sonnet-4-6
      api_key: os.environ/ANTHROPIC_API_KEY
      cache_control_injection_points:
        - location: message
          role: system      
  - model_name: claude-opus-4-7
    litellm_params:
      model: anthropic/claude-opus-4-7
      api_key: os.environ/ANTHROPIC_API_KEY
      cache_control_injection_points:
        - location: message
          role: system      
YAML

  [ -n "${PERPLEXITYAI_API_KEY:-}" ] && cat >> "$MODELS" << 'YAML'
  - model_name: sonar-pro
    litellm_params:
      model: perplexity/sonar-pro
      api_key: os.environ/PERPLEXITYAI_API_KEY
YAML

  [ -n "${CODESTRAL_API_KEY:-}" ] && cat >> "$MODELS" << 'YAML'
  - model_name: codestral
    litellm_params:
      model: codestral/codestral-latest
      api_key: os.environ/CODESTRAL_API_KEY
      api_base: https://codestral.mistral.ai/v1
YAML

  [ -n "${COHERE_API_KEY:-}" ] && cat >> "$MODELS" << 'YAML'
  - model_name: command-r-plus
    litellm_params:
      model: cohere/command-r-plus-08-2024
      api_key: os.environ/COHERE_API_KEY
YAML
fi

# --- search tools ---

SEARCH="$CONFIG_DIR/litellm-search.yaml"
: > "$SEARCH"

HAS_SEARCH=0
for key in PERPLEXITYAI_API_KEY TAVILY_API_KEY; do
  eval "val=\${${key}:-}"
  [ -n "$val" ] && HAS_SEARCH=1 && break
done

if [ "$HAS_SEARCH" = "1" ]; then
  echo "search_tools:" >> "$SEARCH"

  [ -n "${PERPLEXITYAI_API_KEY:-}" ] && cat >> "$SEARCH" << 'YAML'
  - search_tool_name: perplexity-search
    litellm_params:
      search_provider: perplexity
      api_key: os.environ/PERPLEXITYAI_API_KEY
YAML

  [ -n "${TAVILY_API_KEY:-}" ] && cat >> "$SEARCH" << 'YAML'
  - search_tool_name: tavily-search
    litellm_params:
      search_provider: tavily
      api_key: os.environ/TAVILY_API_KEY
YAML
fi

echo "wrote $MODELS"
echo "wrote $SEARCH"
