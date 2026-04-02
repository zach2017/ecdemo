#!/usr/bin/env bash
# =============================================================================
# 10 — Security: Users, Roles, API Keys & RBAC
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 10: Security — Users, Roles, API Keys & RBAC          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 10.1: ROLES ----
section "10.1 — Create Custom Roles"

explain "Read-only role for products"
run_es POST "/_security/role/products-reader" '{
  "indices": [{"names":["products*"],"privileges":["read","view_index_metadata"]}]
}'

explain "Write-only role for logs"
run_es POST "/_security/role/logs-writer" '{
  "indices": [{"names":["weblogs*","app-logs-*"],"privileges":["create_doc","create_index","view_index_metadata"]}]
}'

explain "Role with FIELD-LEVEL security (hide sensitive fields)"
run_es POST "/_security/role/products-limited" '{
  "indices": [{"names":["products*"],"privileges":["read"],
    "field_security":{"grant":["name","category","price","rating","in_stock"]}}]
}'

explain "Role with DOCUMENT-LEVEL security (only Electronics)"
run_es POST "/_security/role/electronics-only" '{
  "indices": [{"names":["products*"],"privileges":["read"],
    "query":{"term":{"category":"Electronics"}}}]
}'

exam_tip "field_security.grant = whitelist. field_security.except = blacklist."
exam_tip "query in role = transparent filter on every search."
pause_step

# ---- 10.2: USERS ----
section "10.2 — Create Users"

run_es POST "/_security/user/viewer" '{"password":"viewer123","roles":["products-reader"],"full_name":"Read Only Viewer"}'
run_es POST "/_security/user/shipper" '{"password":"shipper123","roles":["logs-writer"],"full_name":"Log Shipper"}'
run_es POST "/_security/user/buyer" '{"password":"buyer123","roles":["electronics-only"],"full_name":"Electronics Buyer"}'
run_es POST "/_security/user/analyst" '{"password":"analyst123","roles":["products-limited"],"full_name":"Data Analyst"}'

pause_step

# ---- 10.3: TEST ----
section "10.3 — Test Security Restrictions"

explain "viewer — can read products"
curl -s -u "viewer:viewer123" "$ES/products/_search?size=2&_source=name,price" | python3 -m json.tool 2>/dev/null
echo ""

explain "viewer — blocked from weblogs (expect 403)"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -u "viewer:viewer123" "$ES/weblogs/_search")
echo -e "  HTTP ${RED}${HTTP}${NC} (403 = Forbidden ✓)"
echo ""

explain "buyer — only sees Electronics (document-level security)"
curl -s -u "buyer:buyer123" "$ES/products/_search?size=10&_source=name,category" | python3 -m json.tool 2>/dev/null
echo ""

explain "analyst — limited fields (no description, tags, supplier)"
curl -s -u "analyst:analyst123" "$ES/products/_search?size=2" | python3 -m json.tool 2>/dev/null
echo ""

pause_step

# ---- 10.4: API KEYS ----
section "10.4 — API Keys"

explain "Create a superuser API key (inherits elastic's permissions)"
run_es POST "/_security/api_key" '{
  "name": "admin-key",
  "expiration": "30d"
}'

explain "Create a scoped API key (read-only on products)"
run_es POST "/_security/api_key" '{
  "name": "products-readonly-key",
  "expiration": "7d",
  "role_descriptors": {
    "products-read": {
      "cluster": ["monitor"],
      "indices": [{"names":["products*"],"privileges":["read"]}]
    }
  }
}'

explain "To USE an API key, grab the 'encoded' value from the response above:"
echo -e "${DIM}  curl -H 'Authorization: ApiKey <encoded-value>' http://localhost:9200/products/_search${NC}"
echo ""

explain "List your API keys"
run_es GET "/_security/api_key?owner=true"

explain "Invalidate by name"
run_es DELETE "/_security/api_key" '{"name":"admin-key"}'

exam_tip "No role_descriptors = key inherits creating user's full permissions."
exam_tip "With role_descriptors = INTERSECTION of user perms and key perms."
exam_tip "API keys don't require TLS — they work over plain HTTP too."
pause_step

# ---- 10.5: MANAGE ----
section "10.5 — User Management APIs"

explain "Change password"
run_es POST "/_security/user/viewer/_password" '{"password":"new_viewer_456"}'

explain "Disable a user"
run_es PUT "/_security/user/viewer/_disable"

explain "Re-enable"
run_es PUT "/_security/user/viewer/_enable"

explain "List all custom roles"
echo -e "${DIM}  GET /_security/role/products-reader${NC}"
echo -e "${DIM}  GET /_security/role/logs-writer${NC}"
echo -e "${DIM}  GET /_security/role/electronics-only${NC}"
echo -e "${DIM}  GET /_security/role/products-limited${NC}"

section "EXERCISES"
exercise "Create a role 'error-logs-only' that can read weblogs but only where level='error'"
exercise "Create an API key scoped to write-only on 'app-logs-*' with 24h expiry"
exercise "Create a role that can read all indices but hides the 'client_ip' field"
exercise "Test each user/key with curl to verify restrictions"

echo -e "\n${GREEN}✅ Lab 10 Complete!${NC}"
