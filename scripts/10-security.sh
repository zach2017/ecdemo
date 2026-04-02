#!/usr/bin/env bash
# =============================================================================
# 10 — Security: Users, Roles & RBAC
# =============================================================================
# NOTE: Security is DISABLED in the default dev-mode compose.
#
# To practice these commands live, restart with security enabled:
#
#   docker compose down -v
#   # Edit docker-compose.yml: change xpack.security.enabled to true on es01
#   # Remove es02 (or set discovery.type=single-node on es01)
#   docker compose up -d es01 kibana
#
# OR just study these commands — the exam docs are your main resource anyway.
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 10: Security — Users, Roles & RBAC                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if security is enabled
SEC_CHECK=$(curl -s "$ES/_xpack/security" 2>/dev/null || echo "")
if echo "$SEC_CHECK" | grep -q '"enabled":false\|security_exception'; then
  echo -e "${YELLOW}  ⚠  Security is currently DISABLED in your cluster.${NC}"
  echo -e "${YELLOW}     The commands below are shown for reference and exam study.${NC}"
  echo -e "${YELLOW}     To run them live, see the instructions at the top of this script.${NC}"
  echo ""
  echo -e "${YELLOW}     Quick single-node security setup:${NC}"
  echo -e "${DIM}       1. docker compose down -v${NC}"
  echo -e "${DIM}       2. Edit docker-compose.yml on es01:${NC}"
  echo -e "${DIM}            - xpack.security.enabled=true${NC}"
  echo -e "${DIM}            - discovery.type=single-node${NC}"
  echo -e "${DIM}            - ELASTIC_PASSWORD=examlab2026${NC}"
  echo -e "${DIM}       3. Comment out es02 entirely${NC}"
  echo -e "${DIM}       4. Add to kibana environment:${NC}"
  echo -e "${DIM}            - ELASTICSEARCH_USERNAME=kibana_system${NC}"
  echo -e "${DIM}            - ELASTICSEARCH_PASSWORD=examlab2026${NC}"
  echo -e "${DIM}       5. docker compose up -d${NC}"
  echo -e "${DIM}       6. Set kibana_system password:${NC}"
  echo -e "${DIM}          curl -u elastic:examlab2026 -X POST localhost:9200/_security/user/kibana_system/_password \\${NC}"
  echo -e "${DIM}            -H 'Content-Type: application/json' -d '{\"password\":\"examlab2026\"}'${NC}"
  echo ""
  SHOW_ONLY=true
else
  SHOW_ONLY=false
fi

section "10.1 — Create Custom Roles"

explain "Read-only role for the products index"
if [ "$SHOW_ONLY" = false ]; then
  run_es POST "/_security/role/products-reader" '{
    "indices": [{"names":["products*"],"privileges":["read","view_index_metadata"]}]
  }'
else
  echo -e "${DIM}  POST /_security/role/products-reader${NC}"
  echo -e "${DIM}  { \"indices\": [{\"names\":[\"products*\"],\"privileges\":[\"read\",\"view_index_metadata\"]}] }${NC}"
fi

explain "Role with FIELD-LEVEL security (user can only see certain fields)"
if [ "$SHOW_ONLY" = false ]; then
  run_es POST "/_security/role/products-limited" '{
    "indices": [{"names":["products*"],"privileges":["read"],
      "field_security":{"grant":["name","category","price","rating","in_stock"]}}]
  }'
else
  echo -e "${DIM}  POST /_security/role/products-limited${NC}"
  echo -e "${DIM}  { \"indices\": [{\"names\":[\"products*\"],\"privileges\":[\"read\"],${NC}"
  echo -e "${DIM}    \"field_security\":{\"grant\":[\"name\",\"category\",\"price\",\"rating\"]}}] }${NC}"
fi

explain "Role with DOCUMENT-LEVEL security (user can only see Electronics)"
if [ "$SHOW_ONLY" = false ]; then
  run_es POST "/_security/role/electronics-only" '{
    "indices": [{"names":["products*"],"privileges":["read"],
      "query":{"term":{"category":"Electronics"}}}]
  }'
else
  echo -e "${DIM}  POST /_security/role/electronics-only${NC}"
  echo -e "${DIM}  { \"indices\": [{\"names\":[\"products*\"],\"privileges\":[\"read\"],${NC}"
  echo -e "${DIM}    \"query\":{\"term\":{\"category\":\"Electronics\"}}}] }${NC}"
fi

exam_tip "Field security: 'grant' = whitelist, 'except' = blacklist."
exam_tip "Document security: query filter applied transparently to every search."
pause_step

section "10.2 — Create Users"

explain "Create users and assign roles"
echo -e "${DIM}  POST /_security/user/viewer${NC}"
echo -e "${DIM}  {${NC}"
echo -e "${DIM}    \"password\": \"viewer_pass_123\",${NC}"
echo -e "${DIM}    \"roles\": [\"products-reader\"],${NC}"
echo -e "${DIM}    \"full_name\": \"Read Only Viewer\"${NC}"
echo -e "${DIM}  }${NC}"
echo ""
echo -e "${DIM}  POST /_security/user/electronics-buyer${NC}"
echo -e "${DIM}  {${NC}"
echo -e "${DIM}    \"password\": \"buyer_pass_123\",${NC}"
echo -e "${DIM}    \"roles\": [\"electronics-only\"],${NC}"
echo -e "${DIM}    \"full_name\": \"Electronics Department Buyer\"${NC}"
echo -e "${DIM}  }${NC}"

if [ "$SHOW_ONLY" = false ]; then
  run_es POST "/_security/user/viewer" '{"password":"viewer_pass_123","roles":["products-reader"],"full_name":"Read Only Viewer"}'
  run_es POST "/_security/user/electronics-buyer" '{"password":"buyer_pass_123","roles":["electronics-only"],"full_name":"Electronics Buyer"}'

  section "10.3 — Test Security"
  explain "Search as 'viewer' — should see products"
  echo -e "${BOLD}curl -u viewer:viewer_pass_123 localhost:9200/products/_search?size=2${NC}"
  curl -s -u "viewer:viewer_pass_123" "$ES/products/_search?size=2&_source=name,price" | python3 -m json.tool 2>/dev/null
  echo ""

  explain "Search as 'electronics-buyer' — only sees Electronics"
  echo -e "${BOLD}curl -u electronics-buyer:buyer_pass_123 localhost:9200/products/_search?size=5${NC}"
  curl -s -u "electronics-buyer:buyer_pass_123" "$ES/products/_search?size=5&_source=name,category" | python3 -m json.tool 2>/dev/null
fi

pause_step

section "10.4 — Key Security APIs to Know for the Exam"

echo -e "${BOLD}  Create/manage roles:${NC}"
echo -e "${DIM}    POST /_security/role/<name>     — create or update a role${NC}"
echo -e "${DIM}    GET  /_security/role/<name>      — get a role${NC}"
echo -e "${DIM}    DELETE /_security/role/<name>     — delete a role${NC}"
echo ""
echo -e "${BOLD}  Create/manage users:${NC}"
echo -e "${DIM}    POST /_security/user/<name>     — create or update a user${NC}"
echo -e "${DIM}    GET  /_security/user/<name>      — get a user${NC}"
echo -e "${DIM}    POST /_security/user/<name>/_password — change password${NC}"
echo -e "${DIM}    PUT  /_security/user/<name>/_disable  — disable user${NC}"
echo -e "${DIM}    PUT  /_security/user/<name>/_enable   — enable user${NC}"
echo ""
echo -e "${BOLD}  Role privileges for indices:${NC}"
echo -e "${DIM}    read, write, create_doc, create_index, delete, delete_index,${NC}"
echo -e "${DIM}    manage, view_index_metadata, monitor, all${NC}"
echo ""
echo -e "${BOLD}  Cluster privileges:${NC}"
echo -e "${DIM}    monitor, manage, manage_security, manage_ilm,${NC}"
echo -e "${DIM}    manage_index_templates, manage_pipeline, all${NC}"

exam_tip "Know these APIs cold. The exam will ask you to create specific roles"
exam_tip "with field-level and document-level security from scratch."

section "EXERCISES (when security is enabled)"

exercise "Create a role 'weblog-reader' that can only read weblogs where level='error'"
exercise "Create a user 'ops-team' with both 'weblog-reader' and 'products-reader' roles"
exercise "Create a role with field security that hides 'client_ip' from weblogs"
exercise "Test each user with curl -u <user>:<pass> to verify restrictions work"

echo ""
echo -e "${GREEN}✅ Lab 10 Complete!${NC}"
