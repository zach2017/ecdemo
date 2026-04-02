#!/usr/bin/env bash
# =============================================================================
# 02 — Index Templates & Component Templates
# =============================================================================
# EXAM TOPICS:
#   "Define and use an index template for a given pattern"
#   "Define and use a dynamic template that satisfies a given set of requirements"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 02: Index Templates & Component Templates             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 2.1: COMPONENT TEMPLATES ----
section "2.1 — Component Templates (Reusable Building Blocks)"

explain "Component templates are reusable pieces that index templates compose."
explain "Think of them as 'mix-ins' — settings, mappings, or aliases you use across templates."

explain "Create a component template for common settings"
run_es PUT "/_component_template/base-settings" '{
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-policy",
      "index.routing.allocation.include.temp": "hot"
    }
  }
}'

explain "Create a component template for common log mappings"
run_es PUT "/_component_template/log-mappings" '{
  "template": {
    "mappings": {
      "properties": {
        "@timestamp":  {"type": "date"},
        "message":     {"type": "text"},
        "level":       {"type": "keyword"},
        "service":     {"type": "keyword"},
        "host":        {"type": "keyword"},
        "trace_id":    {"type": "keyword"}
      }
    }
  }
}'

exam_tip "Component templates cannot be used alone — they must be referenced by an index template."

pause_step

# ---- 2.2: INDEX TEMPLATES ----
section "2.2 — Index Templates (Composable)"

explain "An index template matches index name patterns and applies settings/mappings."
explain "This template uses both component templates AND adds its own fields."

run_es PUT "/_index_template/app-logs-template" '{
  "index_patterns": ["app-logs-*"],
  "priority": 200,
  "composed_of": ["base-settings", "log-mappings"],
  "template": {
    "settings": {
      "number_of_shards": 2
    },
    "mappings": {
      "properties": {
        "request_id":    {"type": "keyword"},
        "response_code": {"type": "integer"},
        "duration_ms":   {"type": "float"},
        "user_id":       {"type": "keyword"}
      }
    },
    "aliases": {
      "all-app-logs": {}
    }
  }
}'

explain "Now create an index matching the pattern — template auto-applies!"
run_es PUT "/app-logs-2026.04.01"

explain "Verify the template was applied (check settings and mappings)"
run_es GET "/app-logs-2026.04.01/_mapping"

explain "Index a document — notice it has fields from BOTH component templates"
run_es POST "/app-logs-2026.04.01/_doc" '{
  "@timestamp": "2026-04-01T10:00:00Z",
  "message": "User login successful",
  "level": "info",
  "service": "auth-service",
  "host": "web-01",
  "request_id": "req-abc-123",
  "response_code": 200,
  "duration_ms": 45.2,
  "user_id": "user-42"
}'

exam_tip "Priority matters! Higher priority templates win when patterns overlap."
exam_tip "composed_of order matters — later templates override earlier ones."

pause_step

# ---- 2.3: DYNAMIC TEMPLATES ----
section "2.3 — Dynamic Templates"

explain "Dynamic templates control how ES maps fields it discovers automatically."
explain "Instead of ES guessing, you define rules for unmapped fields."

run_es PUT "/dynamic-demo" '{
  "mappings": {
    "dynamic_templates": [
      {
        "strings_as_keywords": {
          "match_mapping_type": "string",
          "match": "*_code",
          "mapping": { "type": "keyword" }
        }
      },
      {
        "strings_as_text": {
          "match_mapping_type": "string",
          "unmatch": "*_code",
          "mapping": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          }
        }
      },
      {
        "longs_as_integers": {
          "match_mapping_type": "long",
          "mapping": { "type": "integer" }
        }
      },
      {
        "ip_fields": {
          "match": "*_ip",
          "mapping": { "type": "ip" }
        }
      }
    ]
  }
}'

explain "Index a doc — watch dynamic templates control the mapping"
run_es POST "/dynamic-demo/_doc" '{
  "error_code": "ERR_404",
  "status_code": "HTTP_200",
  "description": "Page not found error occurred",
  "count": 42,
  "client_ip": "192.168.1.100",
  "server_ip": "10.0.0.5"
}'

explain "Check the resulting mapping — codes are keyword, IPs are ip type!"
run_es GET "/dynamic-demo/_mapping"

exam_tip "match_mapping_type filters by JSON type (string, long, double, boolean)."
exam_tip "match/unmatch use glob patterns on field names."
exam_tip "path_match works on the full dotted path (e.g., 'user.address.*')."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Create a component template 'metric-mappings' with fields: metric_name (keyword), value (double), unit (keyword), collected_at (date)"
exercise "Create an index template 'infra-metrics-*' that composes base-settings + metric-mappings"
exercise "Create an index 'infra-metrics-2026.04' and verify the template was applied"
exercise "Create a dynamic template where any field ending in '_count' becomes integer and any field ending in '_ratio' becomes float"

echo ""
echo -e "${GREEN}✅ Lab 02 Complete! Next: ./scripts/03-ilm-data-streams.sh${NC}"
