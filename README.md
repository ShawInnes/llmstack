# LLM Stack

Production-oriented stack combining LiteLLM (proxy/gateway) and Langfuse (observability) with shared infrastructure, PII guardrails, and monitoring.

## Quick Start

```bash
touch .env   # add API keys and secrets (see below)
make up      # generates litellm config from .env, then starts all services
```

## Common Commands

| Command | Description |
|---------|-------------|
| `make up` | Generate config + start all services |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make restart svc=litellm` | Restart one service |
| `make logs` | Tail logs for all services |
| `make logs svc=litellm` | Tail logs for one service |
| `make ps` | Show service status |
| `make pull` | Pull latest images |
| `make config` | Regenerate litellm config from `.env` without restarting |
| `make reset` | Destroy all volumes and start fresh |
| `make seed` | Create seed virtual keys in LiteLLM (idempotent) |

## API Keys

Set any combination in `.env` — `make up` generates the LiteLLM config from these before starting:

```bash
# LLM providers (each enables a model in LiteLLM)
OPENAI_API_KEY=sk-...              # → gpt-4o
ANTHROPIC_API_KEY=sk-ant-...       # → claude-sonnet-4-6
PERPLEXITYAI_API_KEY=pplx-...        # → sonar-pro (model + search tool)
CODESTRAL_API_KEY=...              # → codestral-latest
COHERE_API_KEY=...                 # → command-r-plus

# Search tools (available to agents, no model entry)
TAVILY_API_KEY=tvly-...            # → tavily-search tool
SERP_API_KEY=...                   # passed through as env var

# Langfuse → LiteLLM tracing (get from Langfuse UI → Settings → API Keys)
LANGFUSE_PUBLIC_KEY=lf_pk_...
LANGFUSE_SECRET_KEY=lf_sk_...
```

## Services & Endpoints

| Service | URL | Credentials |
|---------|-----|-------------|
| **Langfuse** (web UI) | http://localhost:3000 | `langfuse@langfuse.com` / `langfuse123` (pre-seeded) |
| **LiteLLM** (proxy) | http://localhost:4000 | `LITELLM_MASTER_KEY` |
| **RustFS** (S3 API) | http://localhost:9090 | `rustfsadmin` / `rustfsadmin` |
| **RustFS** (console) | http://localhost:9091 | `rustfsadmin` / `rustfsadmin` |
| **Prometheus** | http://localhost:9092 | No auth |
| **code-server** (VS Code) | http://localhost:8080 | No auth (localhost only) |
| **Postgres** | localhost:5432 | `postgres` / `postgres` |
| **Valkey** | localhost:6379 | password: `myredissecret` |
| **ClickHouse** (HTTP) | localhost:8123 | `clickhouse` / `clickhouse` |
| **ClickHouse** (native) | localhost:9000 | `clickhouse` / `clickhouse` |

> Postgres, Valkey, ClickHouse, RustFS console, code-server, and all exporters are bound to `127.0.0.1` only.

## Architecture

```
                        +------------------+
                        |     LiteLLM      |  :4000
                        |  config gen on   |
                        |     startup      |
                        +--------+---------+
                                 |
          +----------------------+----------------------+
          |                      |                      |
   +------+------+      +--------+-------+    +---------+--------+
   |  Postgres   |      |    Valkey      |    |    Presidio      |
   |   :5432     |      |    :6379       |    | analyzer  :5002  |
   |  litellm DB |      |    cache       |    | anonymizer:5001  |
   |  langfuse DB|      +--------+-------+    +------------------+
   +------+------+               |
          |              +-------+--------+
   +------+------+       |  otel-collector|  :8889 (Valkey metrics)
   | Langfuse    |       +-------+--------+
   | web :3000   |               |
   | worker:3030 |       +-------+--------+
   +------+------+       |   Prometheus   |  :9092
          |              |  scrapes all   |
   +------+------+       | +-----------+  |
   |   RustFS    |       | | pg-export |  |
   | :9090 (S3)  |       | | vk-export |  |
   | :9091 (con) |       | | clickhouse|  |
   +-------------+       | | litellm   |  |
                         | | otel-col  |  |
                         | +-----------+  |
                         +----------------+

   +-------------+
   |  ClickHouse |  :8123 / :9000
   +-------------+
```

## code-server

Browser-based VS Code at `http://localhost:8080` (no password — localhost-only).

On first boot the custom entrypoint (`scripts/code-server-entrypoint.sh`) automatically:

1. Installs Node.js + npm
2. Installs the Claude Code CLI (`~/.local/bin/claude`)
3. Installs the Claude Code VS Code extension

These are persisted in the `codeserver_data` volume — subsequent boots skip installation.

Claude Code is pre-configured to route through LiteLLM:

| Variable | Value |
|----------|-------|
| `ANTHROPIC_AUTH_TOKEN` | `sk-claude-code` |
| `ANTHROPIC_BASE_URL` | `http://litellm:4000` |
| `ANTHROPIC_DEFAULT_MODEL` | `claude-sonnet-4-6` |

The `sk-claude-code` key is seeded into LiteLLM by `make seed`.

## LiteLLM Config Generation

`scripts/generate-litellm-config.sh` runs inside the LiteLLM container before startup and writes `config/litellm-config.yaml` based on which API keys are set. Always-on config:

- **Guardrails** — Presidio PII detection on all pre-call requests (`presidio-pii`)
- **Prompt injection detection** — heuristics + similarity checks for jailbreak, data exfiltration, SQL, malicious code, system prompt
- **Caching** — Redis/Valkey-backed response cache
- **Langfuse tracing** — all LiteLLM calls traced to Langfuse (requires `LANGFUSE_PUBLIC_KEY` + `LANGFUSE_SECRET_KEY` in `.env`)

Conditionally enabled per key:

| Key | Model / Tool |
|-----|-------------|
| `OPENAI_API_KEY` | `gpt-4o` model |
| `ANTHROPIC_API_KEY` | `claude-sonnet-4-6` model |
| `PERPLEXITYAI_API_KEY` | `sonar-pro` model + `perplexity-search` tool |
| `CODESTRAL_API_KEY` | `codestral-latest` model (via `codestral.mistral.ai`) |
| `COHERE_API_KEY` | `command-r-plus-08-2024` model |
| `TAVILY_API_KEY` | `tavily-search` tool |

## Guardrails

| Guardrail | Type | Scope |
|-----------|------|-------|
| Presidio PII | pre_call | Anonymises PII before sending to LLM |
| Prompt injection | callback | Detects injection attempts in requests |

Presidio runs as two local services (`presidio-analyzer`, `presidio-anonymizer`) — no data leaves the stack for PII scanning. Images are `linux/amd64`; on Apple Silicon they run via Rosetta emulation.

## Monitoring

Prometheus scrapes metrics from:

| Source | Via | Port |
|--------|-----|------|
| LiteLLM | direct | 4000 |
| ClickHouse | built-in exporter | 9363 |
| Postgres | `postgres-exporter` | 9187 |
| Valkey | `valkey-exporter` | 9121 |
| Valkey (OTEL) | `otel-collector` | 8889 |
| Prometheus | self | 9090 |

Valkey metrics are collected via both `valkey-exporter` (Prometheus format) and `otel-collector` (OTEL redis receiver → Prometheus exporter, namespaced as `valkey_*`).

## Databases

Shared Postgres instance with separate databases and users:

| Database | User | Password | Used by |
|----------|------|----------|---------|
| `langfuse` | `langfuse` | `langfuse` | Langfuse |
| `litellm` | `litellm` | `litellm` | LiteLLM |
| `postgres` | `postgres` | `postgres` | Admin (default) |

Auto-created on first boot via `scripts/init-databases.sh`.

## Object Storage

RustFS (S3-compatible). Bucket `langfuse` is auto-created on startup by `rustfs-init`.

| Endpoint | URL |
|----------|-----|
| Internal (container) | `http://rustfs:9000` |
| External (host) | `http://localhost:9090` |

## Configuration

Override via `.env` or environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_PASSWORD` | `postgres` | Postgres superuser password |
| `LITELLM_DB_PASSWORD` | `litellm` | LiteLLM DB user password |
| `LANGFUSE_DB_PASSWORD` | `langfuse` | Langfuse DB user password |
| `LITELLM_MASTER_KEY` | auto-generated | LiteLLM admin key (`sk-…`) — generated on first `make config` |
| `LITELLM_SALT_KEY` | auto-generated | Encrypts provider keys at rest in DB — generated on first `make config` |
| `REDIS_AUTH` | `myredissecret` | Valkey auth password |
| `RUSTFS_ACCESS_KEY` | `rustfsadmin` | RustFS access key |
| `RUSTFS_SECRET_KEY` | `rustfsadmin` | RustFS secret key |
| `CLICKHOUSE_USER` | `clickhouse` | ClickHouse user |
| `CLICKHOUSE_PASSWORD` | `clickhouse` | ClickHouse password |
| `ENCRYPTION_KEY` | (zeroed) | Langfuse encryption key — generate: `openssl rand -hex 32` |
| `SALT` | `mysalt` | Langfuse salt |
| `NEXTAUTH_SECRET` | `mysecret` | Langfuse NextAuth secret |
| `CODESERVER_PASSWORD` | — | Not used (auth disabled; access is localhost-only) |

## Volumes

| Volume | Service |
|--------|---------|
| `postgres_data` | Postgres |
| `valkey_data` | Valkey |
| `clickhouse_data` | ClickHouse data |
| `clickhouse_logs` | ClickHouse logs |
| `rustfs_data` | RustFS object storage |
| `prometheus_data` | Prometheus TSDB |
| `codeserver_data` | code-server home dir (Claude Code CLI + extensions) |

## Files

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Full stack definition |
| `config/litellm-config.yaml` | LiteLLM main config — static, includes the two files below |
| `config/litellm-models.yaml` | Generated model_list (overwritten by `make config`) |
| `config/litellm-search.yaml` | Generated search_tools (overwritten by `make config`) |
| `config/otelcol.yaml` | OTel Collector config (Valkey redis receiver) |
| `config/prometheus.yml` | Prometheus scrape config |
| `config/clickhouse-prometheus.xml` | Enables ClickHouse metrics endpoint |
| `scripts/init-databases.sh` | Creates litellm + langfuse Postgres databases on first boot |
| `scripts/generate-litellm-config.sh` | Generates LiteLLM config from available API keys |
| `scripts/code-server-entrypoint.sh` | Installs Claude Code CLI + VS Code extension on first boot |
| `scripts/seed-keys.sh` | Seeds LiteLLM virtual keys (run via `make seed`) |
| `config/code-server.yaml` | code-server daemon config (bind addr, auth) |
| `config/code-server-settings.json` | Default VS Code user settings for code-server |
| `.env` | Secrets and API keys (not committed) |
