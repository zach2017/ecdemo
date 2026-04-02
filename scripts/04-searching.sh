#!/usr/bin/env bash
# =============================================================================
# 04 — Searching Data
# =============================================================================
# EXAM TOPICS:
#   "Write and execute a search query for terms and/or phrases"
#   "Write a Boolean combination of multiple queries and filters"
#   "Write an asynchronous search"
#   "Write a search that utilizes a runtime field"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 04: Searching Data                                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 4.1: TERM-LEVEL QUERIES ----
section "4.1 — Term-Level Queries (exact matching, no analysis)"

explain "term — exact match on keyword fields"
run_es GET "/products/_search" '{
  "query": { "term": { "category": "Electronics" } }
}'

explain "terms — match any of several values"
run_es GET "/products/_search" '{
  "query": { "terms": { "brand": ["SoundMax", "TypeMaster"] } }
}'

explain "range — numeric and date ranges"
run_es GET "/products/_search" '{
  "query": {
    "range": {
      "price": { "gte": 50, "lte": 150 }
    }
  }
}'

explain "range — date range"
run_es GET "/products/_search" '{
  "query": {
    "range": {
      "created_at": { "gte": "2026-01-01", "lt": "2026-04-01" }
    }
  }
}'

explain "exists — find documents where a field is present"
run_es GET "/products/_search" '{
  "query": { "exists": { "field": "supplier.country" } }
}'

explain "wildcard — pattern matching"
run_es GET "/products/_search" '{
  "query": { "wildcard": { "name.keyword": "*Wireless*" } }
}'

exam_tip "term queries work on keyword fields. Using 'term' on analyzed text fields"
exam_tip "will often return 0 results because the indexed tokens differ from input."
pause_step

# ---- 4.2: FULL-TEXT QUERIES ----
section "4.2 — Full-Text Queries (analyzed, relevance scoring)"

explain "match — standard full-text search (analyzes the query string)"
run_es GET "/products/_search" '{
  "query": { "match": { "description": "wireless noise cancelling" } }
}'

explain "match with operator AND (all terms must be present)"
run_es GET "/products/_search" '{
  "query": {
    "match": {
      "description": {
        "query": "wireless battery",
        "operator": "and"
      }
    }
  }
}'

explain "match_phrase — terms must appear in exact order"
run_es GET "/products/_search" '{
  "query": { "match_phrase": { "description": "carbon-plate running" } }
}'

explain "multi_match — search across multiple fields"
run_es GET "/products/_search" '{
  "query": {
    "multi_match": {
      "query": "wireless premium",
      "fields": ["name^3", "description"],
      "type": "best_fields"
    }
  }
}'

explain "query_string — Lucene syntax (power users)"
run_es GET "/products/_search" '{
  "query": {
    "query_string": {
      "query": "(wireless OR bluetooth) AND price:[50 TO 100]",
      "default_field": "description"
    }
  }
}'

exam_tip "multi_match types: best_fields (default), most_fields, cross_fields, phrase"
exam_tip "The ^3 in 'name^3' means the name field is 3x more important than description."
pause_step

# ---- 4.3: BOOL QUERIES ----
section "4.3 — Bool Queries (combining multiple conditions)"

explain "The bool query is the workhorse — combines must, should, filter, must_not."
explain "must = AND (contributes to score)"
explain "filter = AND (no scoring, faster, cached)"
explain "should = OR (boosts score if matched)"
explain "must_not = NOT (excludes, no scoring)"

run_es GET "/products/_search" '{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "wireless" } }
      ],
      "filter": [
        { "term": { "in_stock": true } },
        { "range": { "price": { "lte": 80 } } }
      ],
      "should": [
        { "term": { "brand": "SoundMax" } },
        { "range": { "rating": { "gte": 4.5 } } }
      ],
      "must_not": [
        { "term": { "category": "Sports" } }
      ],
      "minimum_should_match": 1
    }
  }
}'

exam_tip "filter clauses are MUCH faster than must for exact-match conditions."
exam_tip "Always use filter for terms, ranges on keyword/date/numeric fields."
exam_tip "minimum_should_match controls how many should clauses must match."
pause_step

# ---- 4.4: RUNTIME FIELDS ----
section "4.4 — Runtime Fields"

explain "Runtime fields are computed at query time — no reindexing needed!"
explain "Calculate a 'discounted_price' field on the fly:"

run_es GET "/products/_search" '{
  "runtime_mappings": {
    "discounted_price": {
      "type": "double",
      "script": "emit(doc['"'"'price'"'"'].value * 0.9)"
    },
    "price_tier": {
      "type": "keyword",
      "script": "if (doc['"'"'price'"'"'].value < 50) emit('"'"'budget'"'"'); else if (doc['"'"'price'"'"'].value < 150) emit('"'"'mid-range'"'"'); else emit('"'"'premium'"'"')"
    }
  },
  "fields": ["discounted_price", "price_tier"],
  "query": { "match_all": {} },
  "_source": ["name", "price"],
  "size": 5
}'

exam_tip "Runtime fields appear in 'fields' array, not _source."
exam_tip "They use Painless scripts with emit() to return values."
pause_step

# ---- 4.5: ASYNC SEARCH ----
section "4.5 — Asynchronous Search"

explain "Async search runs in background — great for slow queries."
explain "Submit an async search:"

run_es POST "/_async_search?wait_for_completion_timeout=1ms" '{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "wireless" } }
      ],
      "filter": [
        { "range": { "price": { "gte": 20 } } }
      ]
    }
  },
  "aggs": {
    "avg_price": { "avg": { "field": "price" } }
  },
  "size": 5
}'

explain "The response includes an 'id' — use it to poll for results:"
explain "GET /_async_search/<id>"
explain "DELETE /_async_search/<id>  (to clean up)"

exam_tip "Async search is useful when you don't know how long a query will take."
exam_tip "Set wait_for_completion_timeout to get partial results immediately."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Find all products in the 'Kitchen' category that cost more than \$30"
exercise "Search for products with 'coffee' OR 'tea' in the description, but NOT in category 'Sports'"
exercise "Write a multi_match query searching 'name' (boosted 5x) and 'description' for 'premium'"
exercise "Create a runtime field 'value_score' = (rating * sold_count) / price, then sort by it"
exercise "Use match_phrase to find products described as 'non-slip eco-friendly'"

echo ""
echo -e "${GREEN}✅ Lab 04 Complete! Next: ./scripts/05-aggregations.sh${NC}"
