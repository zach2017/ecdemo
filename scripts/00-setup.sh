#!/usr/bin/env bash
# =============================================================================
# 00-setup.sh — Initialize the Exam Lab (insecure dev mode)
# =============================================================================
set -euo pipefail

ES="http://localhost:9200"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Elastic Certified Engineer — Exam Practice Lab Setup      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ---- Step 1: Wait for Elasticsearch ----
echo -e "${YELLOW}[1/4] Waiting for Elasticsearch...${NC}"
until curl -s "$ES/_cluster/health" 2>/dev/null | grep -q '"status"'; do
  echo "      Not ready yet. Retrying in 5s..."
  sleep 5
done
HEALTH=$(curl -s "$ES/_cluster/health?pretty" | grep '"status"' | head -1)
echo -e "${GREEN}      ✓ Cluster is up! ${HEALTH}${NC}"
echo ""

# ---- Step 2: Register snapshot repository ----
echo -e "${YELLOW}[2/4] Registering snapshot repository...${NC}"
curl -s -X PUT "$ES/_snapshot/exam-backups" \
  -H 'Content-Type: application/json' \
  -d '{"type":"fs","settings":{"location":"/usr/share/elasticsearch/backups"}}' > /dev/null
echo -e "${GREEN}      ✓ Snapshot repo 'exam-backups' registered${NC}"
echo ""

# ---- Step 3: Load sample data ----
echo -e "${YELLOW}[3/4] Loading sample data...${NC}"

echo "      Creating products index..."
curl -s -X PUT "$ES/products" -H 'Content-Type: application/json' -d '{
  "settings": {"number_of_shards":1,"number_of_replicas":1},
  "mappings": {"properties": {
    "name":{"type":"text","fields":{"keyword":{"type":"keyword"}}},
    "category":{"type":"keyword"},"brand":{"type":"keyword"},
    "price":{"type":"float"},"rating":{"type":"float"},
    "in_stock":{"type":"boolean"},"tags":{"type":"keyword"},
    "description":{"type":"text"},"created_at":{"type":"date"},
    "sold_count":{"type":"integer"},
    "supplier":{"properties":{"name":{"type":"keyword"},"country":{"type":"keyword"}}}
  }}
}' > /dev/null
curl -s -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' \
  --data-binary "@${DATA_DIR}/products-bulk.ndjson" > /dev/null
echo -e "${GREEN}      ✓ products (15 docs)${NC}"

echo "      Creating suppliers index..."
curl -s -X PUT "$ES/suppliers" -H 'Content-Type: application/json' -d '{
  "mappings": {"properties": {
    "supplier_name":{"type":"keyword"},"contact_email":{"type":"keyword"},
    "phone":{"type":"keyword"},"tier":{"type":"keyword"},
    "region":{"type":"keyword"},"annual_volume":{"type":"integer"}
  }}
}' > /dev/null
curl -s -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' \
  --data-binary "@${DATA_DIR}/suppliers-bulk.ndjson" > /dev/null
echo -e "${GREEN}      ✓ suppliers (8 docs)${NC}"

echo "      Creating weblogs index..."
curl -s -X PUT "$ES/weblogs" -H 'Content-Type: application/json' -d '{
  "mappings": {"properties": {
    "@timestamp":{"type":"date"},"message":{"type":"text"},
    "status_code":{"type":"integer"},"response_time_ms":{"type":"integer"},
    "client_ip":{"type":"ip"},"method":{"type":"keyword"},
    "url":{"type":"text","fields":{"keyword":{"type":"keyword"}}},
    "user_agent":{"type":"text","fields":{"keyword":{"type":"keyword"}}},
    "bytes_sent":{"type":"long"},"server":{"type":"keyword"},
    "level":{"type":"keyword"},
    "geo":{"properties":{"city":{"type":"keyword"},"country":{"type":"keyword"}}}
  }}
}' > /dev/null
awk '{print "{\"index\":{\"_index\":\"weblogs\"}}"; print}' "${DATA_DIR}/weblogs-bulk.ndjson" | \
  curl -s -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' --data-binary @- > /dev/null
echo -e "${GREEN}      ✓ weblogs (20 docs)${NC}"

curl -s -X POST "$ES/_refresh" > /dev/null
echo ""

# ---- Step 4: Verify ----
echo -e "${YELLOW}[4/4] Verifying...${NC}"
for idx in products suppliers weblogs; do
  COUNT=$(curl -s "$ES/${idx}/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
  echo -e "      ${GREEN}✓${NC} ${idx}: ${COUNT} documents"
done
echo ""

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Setup Complete!                                            ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║   Elasticsearch:  http://localhost:9200  (no auth needed)    ║${NC}"
echo -e "${CYAN}║   Kibana:         http://localhost:5601  (no login needed)   ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║   Quick test:   curl http://localhost:9200                   ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║   Now run:  ./scripts/01-index-management.sh                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
