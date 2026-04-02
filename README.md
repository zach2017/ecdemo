# Elastic Certified Engineer — Exam Practice Lab

Insecure dev-mode Docker setup for hands-on practice of every exam topic. No passwords, no TLS, no certs. Just works.

## Quick Start

```bash
cd eck-exam-lab

# Clean start (important if you had a previous attempt)
docker compose down -v

# Start 2-node Elasticsearch + Kibana
docker compose up -d

# Wait ~60 seconds, then verify
curl http://localhost:9200/_cluster/health?pretty

# Load sample data
chmod +x scripts/*.sh
./scripts/00-setup.sh
```

**Elasticsearch:** http://localhost:9200 (no auth)
**Kibana:** http://localhost:5601 → Dev Tools (no login)

## Run the Labs

```bash
./scripts/01-index-management.sh     # Indices, mappings, CRUD, aliases
./scripts/02-index-templates.sh      # Component + index + dynamic templates
./scripts/03-ilm-data-streams.sh     # ILM policies, data streams, rollover
./scripts/04-searching.sh            # term, match, bool, runtime fields
./scripts/05-aggregations.sh         # metric, bucket, pipeline, sub-aggs
./scripts/06-ingest-pipelines.sh     # grok, dissect, date, script processors
./scripts/07-reindex-enrich.sh       # Reindex, update_by_query, enrich
./scripts/08-search-features.sh      # Highlighting, sorting, pagination
./scripts/09-cluster-management.sh   # Health, shard allocation, snapshots
./scripts/10-security.sh             # Users, roles, RBAC (reference mode)
```

Reset and redo:
```bash
./scripts/11-cleanup.sh && ./scripts/00-setup.sh
```

## What's in the Box

**Cluster:** 2 Elasticsearch nodes (es01=hot/zone-a, es02=warm/zone-b) + Kibana
**Version:** Elasticsearch & Kibana 8.18.0
**Security:** Disabled (for zero-friction learning)

**Sample data:**
| Index | Docs | Use |
|---|---|---|
| products | 15 | E-commerce catalog — search, aggs, reindex, enrich |
| weblogs | 20 | Server logs — time-series, ILM, pipelines |
| suppliers | 8 | Lookup table — enrich policy practice |

## Requirements

- Docker Desktop with **4GB+ RAM** (Settings → Resources)
- macOS, Linux, or Windows with WSL2

**Linux only:** `sudo sysctl -w vm.max_map_count=262144`

## Troubleshooting

| Problem | Fix |
|---|---|
| Containers won't start | `docker compose down -v` then `docker compose up -d` |
| Exit code 137 (OOMKilled) | Give Docker more RAM (6GB recommended) |
| Port 9200 already in use | `docker ps` and stop other ES containers |
| `curl: (7) connection refused` | Wait 60s. Check: `docker compose logs es01` |
| Kibana not ready | ES must start first. Give it 90 seconds |

## Nuclear reset
```bash
docker compose down -v    # destroys ALL data
docker compose up -d
./scripts/00-setup.sh
```

## Enabling Security (for Lab 10)

To practice security APIs, switch es01 to single-node mode with security:

```bash
docker compose down -v
```

Edit `docker-compose.yml` — change es01 environment to:
```yaml
  - discovery.type=single-node
  - xpack.security.enabled=true
  - ELASTIC_PASSWORD=examlab2026
```

Comment out the entire `es02` service, then:
```bash
docker compose up -d es01 kibana

# Set kibana_system password
curl -u elastic:examlab2026 -X POST http://localhost:9200/_security/user/kibana_system/_password \
  -H 'Content-Type: application/json' -d '{"password":"examlab2026"}'
```

Add to kibana environment in docker-compose.yml:
```yaml
  - ELASTICSEARCH_USERNAME=kibana_system
  - ELASTICSEARCH_PASSWORD=examlab2026
  - xpack.security.enabled=true
```

Then restart kibana: `docker compose restart kibana`
# ecdemo
