#!/usr/bin/env bash
set -euo pipefail
ES="http://localhost:9200"
PASS="${ELASTIC_PASSWORD:-examlab2026}"
AUTH="elastic:${PASS}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Elastic Certified Engineer — Exam Lab Setup                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}[1/3] Waiting for Elasticsearch...${NC}"
until curl -s -u "$AUTH" "$ES/_cluster/health" 2>/dev/null | grep -q '"status"'; do
  echo "      Not ready. Retrying in 5s..."; sleep 5
done
echo -e "${GREEN}      ✓ Cluster is up!${NC}"

echo -e "${YELLOW}[2/3] Registering snapshot repo...${NC}"
curl -s -u "$AUTH" -X PUT "$ES/_snapshot/exam-backups" \
  -H 'Content-Type: application/json' \
  -d '{"type":"fs","settings":{"location":"/usr/share/elasticsearch/backups"}}' > /dev/null
echo -e "${GREEN}      ✓ exam-backups registered${NC}"

echo -e "${YELLOW}[3/3] Loading sample data...${NC}"

curl -s -u "$AUTH" -X PUT "$ES/products" -H 'Content-Type: application/json' -d '{
  "settings":{"number_of_shards":1,"number_of_replicas":0},
  "mappings":{"properties":{
    "name":{"type":"text","fields":{"keyword":{"type":"keyword"}}},
    "category":{"type":"keyword"},"brand":{"type":"keyword"},
    "price":{"type":"float"},"rating":{"type":"float"},
    "in_stock":{"type":"boolean"},"tags":{"type":"keyword"},
    "description":{"type":"text"},"created_at":{"type":"date"},
    "sold_count":{"type":"integer"},
    "supplier":{"properties":{"name":{"type":"keyword"},"country":{"type":"keyword"}}}
  }}
}' > /dev/null
curl -s -u "$AUTH" -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' \
  --data-binary "@${DATA_DIR}/products-bulk.ndjson" > /dev/null
echo -e "${GREEN}      ✓ products${NC}"

curl -s -u "$AUTH" -X PUT "$ES/suppliers" -H 'Content-Type: application/json' -d '{
  "mappings":{"properties":{
    "supplier_name":{"type":"keyword"},"contact_email":{"type":"keyword"},
    "phone":{"type":"keyword"},"tier":{"type":"keyword"},
    "region":{"type":"keyword"},"annual_volume":{"type":"integer"}
  }}
}' > /dev/null
curl -s -u "$AUTH" -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' \
  --data-binary "@${DATA_DIR}/suppliers-bulk.ndjson" > /dev/null
echo -e "${GREEN}      ✓ suppliers${NC}"

curl -s -u "$AUTH" -X PUT "$ES/weblogs" -H 'Content-Type: application/json' -d '{
  "mappings":{"properties":{
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
  curl -s -u "$AUTH" -X POST "$ES/_bulk" -H 'Content-Type: application/x-ndjson' --data-binary @- > /dev/null
echo -e "${GREEN}      ✓ weblogs${NC}"

curl -s -u "$AUTH" -X POST "$ES/_refresh" > /dev/null
echo ""

for idx in products suppliers weblogs; do
  COUNT=$(curl -s -u "$AUTH" "$ES/${idx}/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
  echo -e "      ${GREEN}✓${NC} ${idx}: ${COUNT} docs"
done

echo ""
echo -e "${CYAN}  Elasticsearch:  http://localhost:9200   (elastic / ${PASS})${NC}"
echo -e "${CYAN}  Kibana:         http://localhost:5601   (elastic / ${PASS})${NC}"
echo -e "${CYAN}  API key test:   curl -u elastic:${PASS} -X POST localhost:9200/_security/api_key \\${NC}"
echo -e "${CYAN}                    -H 'Content-Type: application/json' -d '{\"name\":\"test-key\"}'${NC}"
echo ""
echo -e "${GREEN}  Run: ./scripts/01-index-management.sh${NC}"
