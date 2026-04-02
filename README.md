# Elastic Certified Engineer — Exam Practice Lab

Single-node Elasticsearch + Kibana with security ON, API keys, users/roles — no TLS, no certs.

## Quick Start

```bash
cd eck-exam-lab

docker compose down -v        # always start clean
docker compose up -d          # starts: es-setup → es01 → kibana

# wait ~90 seconds then test
curl -u elastic:examlab2026 http://localhost:9200

examlab2026

# load sample data
chmod +x scripts/*.sh
./scripts/00-setup.sh
```

| Service | URL | Login |
|---|---|---|
| Elasticsearch | http://localhost:9200 | `elastic` / `examlab2026` |
| Kibana | http://localhost:5601 | `elastic` / `examlab2026` |

## Generate an API Key

```bash
curl -u elastic:examlab2026 -X POST http://localhost:9200/_security/api_key \
  -H 'Content-Type: application/json' \
  -d '{"name":"my-key","expiration":"30d"}'

# Use the "encoded" value from the response:
curl -H "Authorization: ApiKey <encoded>" http://localhost:9200/_cluster/health
```

## Run the Labs

```bash
./scripts/01-index-management.sh     # Indices, mappings, CRUD, aliases
./scripts/02-index-templates.sh      # Component + index + dynamic templates
./scripts/03-ilm-data-streams.sh     # ILM policies, data streams
./scripts/04-searching.sh            # term, match, bool, runtime fields
./scripts/05-aggregations.sh         # metric, bucket, pipeline aggs
./scripts/06-ingest-pipelines.sh     # grok, dissect, script processors
./scripts/07-reindex-enrich.sh       # Reindex, update_by_query, enrich
./scripts/08-search-features.sh      # Highlighting, sorting, pagination
./scripts/09-cluster-management.sh   # Health, shard allocation, snapshots
./scripts/10-security.sh             # Users, roles, API keys, RBAC
./scripts/11-cleanup.sh              # Reset everything
```

## Architecture

```
es-setup (sets kibana_system password → exits)
    ↓
  es01 (single-node, security ON, no TLS)
    ↓
  kibana (connects as kibana_system)
```

- **Security:** ON (users, roles, API keys all work)
- **HTTP TLS:** OFF (plain `curl` without `-k`)
- **Transport TLS:** Not needed (single-node)
- **License:** Trial (30 days of all features)

## Requirements

- Docker Desktop with **4GB+ RAM**
- macOS / Linux / Windows WSL2

## Troubleshooting

```bash
# Nuclear reset
docker compose down -v && docker compose up -d

# Check ES logs
docker compose logs es01

# Check setup container
docker compose logs setup

# Check all containers
docker compose ps
```

| Problem | Fix |
|---|---|
| Exit code 78 | `docker compose down -v` (clears stale data) |
| Exit code 137 | Give Docker more RAM (6GB) |
| Kibana not ready | Wait 90s. Setup container must finish first |
| 401 Unauthorized | Password is `examlab2026` (check .env) |
