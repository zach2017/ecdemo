#!/usr/bin/env bash
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}  Resetting lab...${NC}"
echo -e "${YELLOW}  Press ENTER or Ctrl+C to cancel${NC}"; read -r

for u in viewer shipper buyer analyst ops-team; do
  curl -s -u "$AUTH" -X DELETE "$ES/_security/user/$u" > /dev/null 2>&1; done
for r in products-reader logs-writer products-limited electronics-only error-logs-only index-admin weblog-reader; do
  curl -s -u "$AUTH" -X DELETE "$ES/_security/role/$r" > /dev/null 2>&1; done
echo -e "${GREEN}  ✓ Users & roles${NC}"

curl -s -u "$AUTH" -X DELETE "$ES/_data_stream/ds-logs-*" > /dev/null 2>&1
curl -s -u "$AUTH" -X DELETE "$ES/_data_stream/ds-metrics-*" > /dev/null 2>&1
echo -e "${GREEN}  ✓ Data streams${NC}"

curl -s -u "$AUTH" -X DELETE "$ES/products,products-v2,products-in-stock,products-discounted,products-enriched,products-restore-test" > /dev/null 2>&1
curl -s -u "$AUTH" -X DELETE "$ES/suppliers,weblogs,weblogs-v2" > /dev/null 2>&1
curl -s -u "$AUTH" -X DELETE "$ES/blog-posts,dynamic-demo,auto-pipeline-index" > /dev/null 2>&1
curl -s -u "$AUTH" -X DELETE "$ES/app-logs-*,infra-metrics-*,movies" > /dev/null 2>&1
echo -e "${GREEN}  ✓ Indices${NC}"

for t in app-logs-template ds-logs-template infra-metrics-template; do
  curl -s -u "$AUTH" -X DELETE "$ES/_index_template/$t" > /dev/null 2>&1; done
for c in base-settings log-mappings ds-log-settings ds-log-mappings metric-mappings; do
  curl -s -u "$AUTH" -X DELETE "$ES/_component_template/$c" > /dev/null 2>&1; done
echo -e "${GREEN}  ✓ Templates${NC}"

for p in logs-policy metrics-policy; do
  curl -s -u "$AUTH" -X DELETE "$ES/_ilm/policy/$p" > /dev/null 2>&1; done
for i in basic-pipeline apache-log-parser dissect-pipeline script-pipeline enrich-supplier; do
  curl -s -u "$AUTH" -X DELETE "$ES/_ingest/pipeline/$i" > /dev/null 2>&1; done
curl -s -u "$AUTH" -X DELETE "$ES/_enrich/policy/supplier-policy" > /dev/null 2>&1
echo -e "${GREEN}  ✓ Pipelines & policies${NC}"

echo -e "\n${GREEN}✅ Reset. Run ./scripts/00-setup.sh to reload.${NC}"
