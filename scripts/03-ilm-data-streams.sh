#!/usr/bin/env bash
# =============================================================================
# 03 — ILM Policies & Data Streams
# =============================================================================
# EXAM TOPICS:
#   "Define an Index Lifecycle Management policy for a time-series index"
#   "Define an index template that creates a new data stream"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 03: ILM Policies & Data Streams                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 3.1: ILM POLICY ----
section "3.1 — Create an ILM Policy"

explain "ILM manages the lifecycle of time-series data through phases:"
explain "  HOT  → actively writing, highest performance storage"
explain "  WARM → no longer writing, still queried, can shrink/force-merge"
explain "  COLD → rarely queried, frozen, cheapest storage"
explain "  DELETE → remove entirely after retention period"

run_es PUT "/_ilm/policy/logs-policy" '{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "1d",
            "max_docs": 1000
          },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "2d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 },
          "set_priority": { "priority": 50 },
          "allocate": {
            "include": { "temp": "warm" }
          }
        }
      },
      "cold": {
        "min_age": "7d",
        "actions": {
          "set_priority": { "priority": 0 },
          "freeze": {}
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'

explain "Verify the policy"
run_es GET "/_ilm/policy/logs-policy"

exam_tip "rollover triggers: max_age, max_docs, max_size, max_primary_shard_size"
exam_tip "min_age in warm/cold/delete is relative to rollover time, not creation!"
exam_tip "shrink reduces shard count. forcemerge reduces Lucene segments (saves disk)."

pause_step

# ---- 3.2: DATA STREAM SETUP ----
section "3.2 — Create a Data Stream"

explain "Data streams are the modern way to handle time-series data."
explain "They require: component template + index template + ILM policy."
explain "Step 1: We already have our ILM policy (logs-policy)."
explain "Step 2: Create a component template for the data stream."

run_es PUT "/_component_template/ds-log-settings" '{
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-policy",
      "number_of_shards": 1,
      "number_of_replicas": 1
    }
  }
}'

run_es PUT "/_component_template/ds-log-mappings" '{
  "template": {
    "mappings": {
      "properties": {
        "@timestamp":      {"type": "date"},
        "message":         {"type": "text"},
        "level":           {"type": "keyword"},
        "service.name":    {"type": "keyword"},
        "host.name":       {"type": "keyword"},
        "http.status_code": {"type": "integer"},
        "http.method":     {"type": "keyword"},
        "url.path":        {"type": "keyword"},
        "event.duration":  {"type": "long"}
      }
    }
  }
}'

explain "Step 3: Create index template with data_stream enabled"
run_es PUT "/_index_template/ds-logs-template" '{
  "index_patterns": ["ds-logs-*"],
  "data_stream": {},
  "priority": 500,
  "composed_of": ["ds-log-settings", "ds-log-mappings"]
}'

explain "Step 4: Write to the data stream (it auto-creates!)"
run_es POST "/ds-logs-app/_doc" '{
  "@timestamp": "2026-04-01T08:00:00Z",
  "message": "Application started successfully",
  "level": "info",
  "service.name": "order-service",
  "host.name": "pod-abc-123"
}'

explain "Write a few more docs"
run_es POST "/ds-logs-app/_bulk" '
{"create":{}}
{"@timestamp":"2026-04-01T08:01:00Z","message":"Processing order #1001","level":"info","service.name":"order-service","host.name":"pod-abc-123","http.status_code":200,"http.method":"POST","url.path":"/api/orders","event.duration":125000000}
{"create":{}}
{"@timestamp":"2026-04-01T08:02:00Z","message":"Payment gateway timeout","level":"error","service.name":"payment-service","host.name":"pod-def-456","http.status_code":504,"http.method":"POST","url.path":"/api/payments","event.duration":30000000000}
{"create":{}}
{"@timestamp":"2026-04-01T08:03:00Z","message":"Inventory check complete","level":"info","service.name":"inventory-service","host.name":"pod-ghi-789","http.status_code":200,"http.method":"GET","url.path":"/api/inventory","event.duration":45000000}
{"create":{}}
{"@timestamp":"2026-04-01T08:04:00Z","message":"User authentication failed","level":"warn","service.name":"auth-service","host.name":"pod-jkl-012","http.status_code":401,"http.method":"POST","url.path":"/api/auth","event.duration":890000000}
'

explain "Check the data stream"
run_es GET "/_data_stream/ds-logs-app"

explain "Search the data stream (just like a normal index)"
run_es GET "/ds-logs-app/_search?size=3"

exam_tip "Data streams use 'create' in _bulk (not 'index'). This is critical!"
exam_tip "Data streams always require @timestamp field."
exam_tip "You cannot update/delete individual docs directly — use update_by_query."

pause_step

# ---- 3.3: CHECK ILM STATUS ----
section "3.3 — Monitor ILM Progress"

explain "Check which ILM phase an index is in"
run_es GET "/ds-logs-app/_ilm/explain"

explain "For lab speed, you can manually trigger ILM to move to next step"
explain "(In production this happens automatically based on min_age)"
run_es POST "/ds-logs-app/_rollover"

explain "Check the data stream again — see the new backing index"
run_es GET "/_data_stream/ds-logs-app"

# ---- EXERCISES ----
section "EXERCISES"

exercise "Create an ILM policy called 'metrics-policy' with: hot (rollover at 30d or 10gb), warm (shrink to 1 shard after 60d), delete after 365d"
exercise "Create a data stream called 'ds-metrics-infra' using your new policy"
exercise "Write 5 metric documents to it with @timestamp, metric_name, value, and host"
exercise "Manually rollover the data stream and verify 2 backing indices exist"

echo ""
echo -e "${GREEN}✅ Lab 03 Complete! Next: ./scripts/04-searching.sh${NC}"
