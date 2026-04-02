#!/usr/bin/env bash
# =============================================================================
# 07 — Reindex, Update By Query & Enrich Policies
# =============================================================================
# EXAM TOPICS:
#   "Use the Reindex API and Update By Query API"
#   "Define and use an enrich processor"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 07: Reindex, Update By Query & Enrich                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 7.1: REINDEX ----
section "7.1 — Reindex API"

explain "Reindex copies documents from one index to another."
explain "Use cases: change mappings, change shard count, rename an index."

explain "Simple reindex — copy products to a new index"
run_es PUT "/products-v2" '{
  "settings": { "number_of_shards": 2, "number_of_replicas": 1 },
  "mappings": {
    "properties": {
      "name":        {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
      "category":    {"type": "keyword"},
      "brand":       {"type": "keyword"},
      "price":       {"type": "scaled_float", "scaling_factor": 100},
      "rating":      {"type": "half_float"},
      "in_stock":    {"type": "boolean"},
      "tags":        {"type": "keyword"},
      "description": {"type": "text"},
      "created_at":  {"type": "date"},
      "sold_count":  {"type": "integer"}
    }
  }
}'

run_es POST "/_reindex" '{
  "source": { "index": "products" },
  "dest":   { "index": "products-v2" }
}'

explain "Reindex with a query filter — only in-stock items"
run_es POST "/_reindex" '{
  "source": {
    "index": "products",
    "query": { "term": { "in_stock": true } }
  },
  "dest": { "index": "products-in-stock" }
}'

explain "Reindex with a script — transform data during copy"
run_es POST "/_reindex" '{
  "source": { "index": "products" },
  "dest":   { "index": "products-discounted" },
  "script": {
    "source": "ctx._source.original_price = ctx._source.price; ctx._source.price = ctx._source.price * 0.85; ctx._source.discount_applied = true"
  }
}'

explain "Check results"
run_es GET "/products-discounted/_search?size=2&_source=name,price,original_price,discount_applied"

exam_tip "Reindex can also work across clusters with 'source.remote'!"
exam_tip "Use 'dest.pipeline' to apply an ingest pipeline during reindex."
pause_step

# ---- 7.2: UPDATE BY QUERY ----
section "7.2 — Update By Query"

explain "Updates documents in-place matching a query — no reindex needed."

explain "Add a 'popular' tag to all products with sold_count > 2000"
run_es POST "/products/_update_by_query" '{
  "query": {
    "range": { "sold_count": { "gt": 2000 } }
  },
  "script": {
    "source": "if (ctx._source.tags == null) ctx._source.tags = []; if (!ctx._source.tags.contains('"'"'popular'"'"')) ctx._source.tags.add('"'"'popular'"'"')"
  }
}'

explain "Set a default value where a field is missing"
run_es POST "/products/_update_by_query" '{
  "query": {
    "bool": {
      "must_not": { "exists": { "field": "discount_percent" } }
    }
  },
  "script": {
    "source": "ctx._source.discount_percent = 0"
  }
}'

explain "Verify — check a popular product"
run_es GET "/products/_search?size=3&_source=name,tags,sold_count,discount_percent" '{
  "query": { "term": { "tags": "popular" } }
}'

exam_tip "update_by_query can use conflicts=proceed to skip version conflicts."
exam_tip "Add ?wait_for_completion=false for background execution on large indices."
pause_step

# ---- 7.3: ENRICH POLICY ----
section "7.3 — Enrich Policy & Processor"

explain "Enrich policies let you join data from a lookup index into incoming docs."
explain "We'll enrich product docs with supplier details from the 'suppliers' index."

explain "Step 1: Create an enrich policy"
run_es PUT "/_enrich/policy/supplier-policy" '{
  "match": {
    "indices": "suppliers",
    "match_field": "supplier_name",
    "enrich_fields": ["contact_email", "phone", "tier", "region", "annual_volume"]
  }
}'

explain "Step 2: Execute the policy (builds the enrich index)"
run_es POST "/_enrich/policy/supplier-policy/_execute"

explain "Step 3: Create a pipeline that uses the enrich processor"
run_es PUT "/_ingest/pipeline/enrich-supplier" '{
  "processors": [
    {
      "enrich": {
        "policy_name": "supplier-policy",
        "field": "supplier.name",
        "target_field": "supplier_info",
        "max_matches": 1
      }
    }
  ]
}'

explain "Step 4: Test with _simulate"
run_es POST "/_ingest/pipeline/enrich-supplier/_simulate" '{
  "docs": [
    {
      "_source": {
        "name": "Test Widget",
        "supplier": { "name": "TechDistro Inc", "country": "US" }
      }
    }
  ]
}'

explain "Step 5: Reindex products with enrichment"
run_es POST "/_reindex" '{
  "source": { "index": "products" },
  "dest": {
    "index": "products-enriched",
    "pipeline": "enrich-supplier"
  }
}'

explain "Check enriched results"
run_es GET "/products-enriched/_search?size=2&_source=name,supplier,supplier_info"

exam_tip "Enrich policies must be EXECUTED after creation and after source data changes."
exam_tip "The enrich index is read-only — you can't modify it directly."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Reindex 'weblogs' to 'weblogs-v2' but only include docs where status_code >= 400"
exercise "Use update_by_query to add a 'slow' tag to weblogs with response_time_ms > 500"
exercise "Create an enrich policy that enriches weblogs with geo data from a custom 'geo-lookup' index"

echo ""
echo -e "${GREEN}✅ Lab 07 Complete! Next: ./scripts/08-search-features.sh${NC}"
