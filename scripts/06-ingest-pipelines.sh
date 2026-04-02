#!/usr/bin/env bash
# =============================================================================
# 06 — Ingest Pipelines & Processors
# =============================================================================
# EXAM TOPICS:
#   "Define and use an ingest pipeline with processors"
#   "Use grok, date, set, rename, remove, script, dissect processors"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 06: Ingest Pipelines & Processors                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 6.1: BASIC PIPELINE ----
section "6.1 — Create a Basic Ingest Pipeline"

explain "Pipelines process documents before they're indexed."
explain "This pipeline: lowercases a field, adds a timestamp, sets a default."

run_es PUT "/_ingest/pipeline/basic-pipeline" '{
  "description": "Basic processing: lowercase, timestamp, defaults",
  "processors": [
    {
      "lowercase": { "field": "level" }
    },
    {
      "set": {
        "field": "processed_at",
        "value": "{{_ingest.timestamp}}"
      }
    },
    {
      "set": {
        "field": "environment",
        "value": "production",
        "override": false
      }
    },
    {
      "rename": {
        "field": "msg",
        "target_field": "message",
        "ignore_missing": true
      }
    }
  ]
}'

explain "Test the pipeline with _simulate (doesn't actually index)"
run_es POST "/_ingest/pipeline/basic-pipeline/_simulate" '{
  "docs": [
    {
      "_source": {
        "msg": "User logged in",
        "level": "INFO",
        "user": "alice"
      }
    },
    {
      "_source": {
        "msg": "Disk space low",
        "level": "WARNING",
        "user": "system",
        "environment": "staging"
      }
    }
  ]
}'

exam_tip "_simulate is your best friend for debugging pipelines!"
exam_tip "override:false means keep existing value if field already exists."
pause_step

# ---- 6.2: GROK PROCESSOR ----
section "6.2 — Grok Processor (Parse Unstructured Text)"

explain "Grok uses regex patterns with named captures to parse log lines."
explain "This pipeline parses Apache Combined Log Format."

run_es PUT "/_ingest/pipeline/apache-log-parser" '{
  "description": "Parse Apache access log lines",
  "processors": [
    {
      "grok": {
        "field": "raw_log",
        "patterns": [
          "%{IP:client_ip} - %{DATA:user} \\[%{HTTPDATE:raw_timestamp}\\] \"%{WORD:method} %{URIPATHPARAM:url} HTTP/%{NUMBER:http_version}\" %{NUMBER:status_code:int} %{NUMBER:bytes_sent:int}"
        ]
      }
    },
    {
      "date": {
        "field": "raw_timestamp",
        "formats": ["dd/MMM/yyyy:HH:mm:ss Z"],
        "target_field": "@timestamp"
      }
    },
    {
      "remove": {
        "field": ["raw_log", "raw_timestamp"]
      }
    },
    {
      "set": {
        "field": "level",
        "value": "error",
        "if": "ctx.status_code >= 400"
      }
    },
    {
      "set": {
        "field": "level",
        "value": "info",
        "if": "ctx.status_code < 400"
      }
    }
  ]
}'

explain "Simulate with real Apache log lines"
run_es POST "/_ingest/pipeline/apache-log-parser/_simulate" '{
  "docs": [
    {"_source": {"raw_log": "192.168.1.100 - frank [01/Apr/2026:08:12:33 +0000] \"GET /api/products HTTP/1.1\" 200 12450"}},
    {"_source": {"raw_log": "203.0.113.50 - - [01/Apr/2026:08:13:30 +0000] \"POST /api/auth/login HTTP/1.1\" 401 290"}}
  ]
}'

exam_tip "Common grok patterns: %{IP}, %{WORD}, %{DATA}, %{GREEDYDATA},"
exam_tip "  %{NUMBER}, %{HTTPDATE}, %{URIPATHPARAM}, %{TIMESTAMP_ISO8601}"
exam_tip "Use :int or :float after field name for type conversion."
pause_step

# ---- 6.3: DISSECT PROCESSOR ----
section "6.3 — Dissect Processor (Faster Alternative to Grok)"

explain "Dissect uses delimiters instead of regex — much faster for structured logs."

run_es PUT "/_ingest/pipeline/dissect-pipeline" '{
  "description": "Parse key=value style logs with dissect",
  "processors": [
    {
      "dissect": {
        "field": "raw_log",
        "pattern": "%{ts} %{+ts} level=%{level} service=%{service} msg=\"%{message}\""
      }
    },
    {
      "date": {
        "field": "ts",
        "formats": ["yyyy-MM-dd HH:mm:ss"],
        "target_field": "@timestamp"
      }
    },
    {
      "remove": { "field": ["raw_log", "ts"] }
    }
  ]
}'

run_es POST "/_ingest/pipeline/dissect-pipeline/_simulate" '{
  "docs": [
    {"_source": {"raw_log": "2026-04-01 08:15:33 level=error service=payment msg=\"Transaction timeout after 30s\""}}
  ]
}'

exam_tip "Dissect is faster than grok but less flexible. Use dissect for"
exam_tip "  consistent formats, grok for variable formats."
pause_step

# ---- 6.4: SCRIPT PROCESSOR ----
section "6.4 — Script Processor (Painless Scripts)"

explain "For complex logic that other processors can't handle."

run_es PUT "/_ingest/pipeline/script-pipeline" '{
  "description": "Compute derived fields with Painless",
  "processors": [
    {
      "script": {
        "source": "ctx.price_category = ctx.price < 50 ? '"'"'budget'"'"' : ctx.price < 150 ? '"'"'standard'"'"' : '"'"'premium'"'"'"
      }
    },
    {
      "script": {
        "source": "ctx.tag_count = ctx.tags != null ? ctx.tags.size() : 0"
      }
    }
  ]
}'

run_es POST "/_ingest/pipeline/script-pipeline/_simulate" '{
  "docs": [
    {"_source": {"name": "Widget A", "price": 29.99, "tags": ["sale", "new"]}},
    {"_source": {"name": "Widget B", "price": 199.00, "tags": ["premium"]}}
  ]
}'

# ---- 6.5: USE PIPELINE ON INDEX ----
section "6.5 — Apply Pipeline When Indexing"

explain "Use ?pipeline= parameter or set a default pipeline on the index"

explain "Method 1: Specify pipeline per request"
run_es POST "/products/_doc?pipeline=script-pipeline" '{
  "name": "Test Product Pipeline",
  "price": 75.00,
  "tags": ["test", "pipeline", "demo"],
  "category": "Test",
  "brand": "TestBrand",
  "rating": 4.0,
  "in_stock": true,
  "description": "Testing pipeline application",
  "created_at": "2026-04-01T12:00:00Z",
  "sold_count": 0
}'

explain "Method 2: Set default pipeline on an index"
run_es PUT "/auto-pipeline-index" '{
  "settings": {
    "default_pipeline": "basic-pipeline"
  }
}'

# ---- EXERCISES ----
section "EXERCISES"

exercise "Create a grok pipeline that parses: '2026-04-01 ERROR [main] com.app.Service - Connection refused' into timestamp, level, thread, class, message"
exercise "Create a pipeline with an uppercase processor on 'method' field and a convert processor to turn 'status' from string to integer"
exercise "Use the _simulate API to test your pipeline with 3 sample docs"

echo ""
echo -e "${GREEN}✅ Lab 06 Complete! Next: ./scripts/07-reindex-enrich.sh${NC}"
