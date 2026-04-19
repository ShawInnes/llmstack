#!/bin/bash
set -e

# Create the litellm database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER litellm WITH PASSWORD '${LITELLM_DB_PASSWORD:-litellm}';
    CREATE DATABASE litellm OWNER litellm;
    GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;
EOSQL

# Create the langfuse database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER langfuse WITH PASSWORD '${LANGFUSE_DB_PASSWORD:-langfuse}';
    CREATE DATABASE langfuse OWNER langfuse;
    GRANT ALL PRIVILEGES ON DATABASE langfuse TO langfuse;
EOSQL
