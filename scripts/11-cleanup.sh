#!/usr/bin/env bash
# =============================================================================
# 11-cleanup.sh — Reset the Lab Environment
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Resetting Lab Environment                                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This will delete ALL lab indices, templates, pipelines.${NC}"
echo -e "${YELLOW}Press ENTER to continue or Ctrl+C to cancel...${NC}"
read -r

echo -e "${YELLOW}[1/6] Deleting data streams...${NC}"
curl -s -X DELETE "$ES/_data_stream/ds-logs-*" > /dev/null 2>&1
curl -s -X DELETE "$ES/_data_stream/ds-metrics-*" > /dev/null 2>&1
echo -e "${GREEN}      ✓ Done${NC}"

echo -e "${YELLOW}[2/6] Deleting indices...${NC}"
curl -s -X DELETE "$ES/products,products-v2,products-in-stock,products-discounted,products-enriched,products-restore-test" > /dev/null 2>&1
curl -s -X DELETE "$ES/suppliers,weblogs,weblogs-v2" > /dev/null 2>&1
curl -s -X DELETE "$ES/blog-posts,dynamic-demo,auto-pipeline-index" > /dev/null 2>&1
curl -s -X DELETE "$ES/app-logs-*,infra-metrics-*,movies" > /dev/null 2>&1
echo -e "${GREEN}      ✓ Done${NC}"

echo -e "${YELLOW}[3/6] Deleting index templates...${NC}"
for tmpl in app-logs-template ds-logs-template infra-metrics-template; do
  curl -s -X DELETE "$ES/_index_template/$tmpl" > /dev/null 2>&1
done
echo -e "${GREEN}      ✓ Done${NC}"

echo -e "${YELLOW}[4/6] Deleting component templates...${NC}"
for ct in base-settings log-mappings ds-log-settings ds-log-mappings metric-mappings; do
  curl -s -X DELETE "$ES/_component_template/$ct" > /dev/null 2>&1
done
echo -e "${GREEN}      ✓ Done${NC}"

echo -e "${YELLOW}[5/6] Deleting ILM policies...${NC}"
for policy in logs-policy metrics-policy; do
  curl -s -X DELETE "$ES/_ilm/policy/$policy" > /dev/null 2>&1
done
echo -e "${GREEN}      ✓ Done${NC}"

echo -e "${YELLOW}[6/6] Deleting ingest pipelines and enrich policies...${NC}"
for pipe in basic-pipeline apache-log-parser dissect-pipeline script-pipeline enrich-supplier; do
  curl -s -X DELETE "$ES/_ingest/pipeline/$pipe" > /dev/null 2>&1
done
curl -s -X DELETE "$ES/_enrich/policy/supplier-policy" > /dev/null 2>&1
echo -e "${GREEN}      ✓ Done${NC}"

echo ""
echo -e "${GREEN}✅ Reset complete! Run ./scripts/00-setup.sh to reload data.${NC}"
