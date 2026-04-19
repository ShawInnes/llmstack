.PHONY: up down restart logs ps config reset pull seed help

help:
	@echo "Usage: make [target] [svc=<service>]"
	@echo ""
	@echo "  up               Generate config + start all services"
	@echo "  down             Stop all services"
	@echo "  restart          Restart all services"
	@echo "  restart svc=X    Restart one service"
	@echo "  logs             Tail logs (all services)"
	@echo "  logs svc=X       Tail logs (one service)"
	@echo "  ps               Show service status"
	@echo "  pull             Pull latest images"
	@echo "  config           Regenerate litellm config from .env (no restart)"
	@echo "  reset            Destroy all volumes and start fresh"
	@echo "  seed             Create seed virtual keys in LiteLLM"

.DEFAULT_GOAL := help

# Generate litellm config from .env, then start all services
up: config
	docker compose up -d

# Stop all services
down:
	docker compose down

# Stop, remove volumes, regenerate config, start fresh
reset:
	docker compose down -v

# Restart all (or specific service: make restart svc=litellm)
restart:
	docker compose restart $(svc)

# Follow logs (all, or specific: make logs svc=litellm)
logs:
	docker compose logs -f $(svc)

# Service status
ps:
	docker compose ps

# Pull latest images
pull:
	docker compose pull

# Generate config/litellm-config.yaml from .env (runs on host)
config:
	./scripts/generate-litellm-config.sh

# Create seed virtual keys in LiteLLM (idempotent)
seed:
	./scripts/seed-keys.sh
