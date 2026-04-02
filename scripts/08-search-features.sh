#!/usr/bin/env bash
# =============================================================================
# 08 — Developing Search Applications
# =============================================================================
# EXAM TOPICS:
#   "Highlight the search terms in the response of a query"
#   "Sort the results of a query by a given set of requirements"
#   "Implement pagination of the results of a search query"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 08: Search Application Features                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 8.1: HIGHLIGHTING ----
section "8.1 — Highlighting Search Terms"

explain "Highlights wrap matched terms in <em> tags (configurable)."

run_es GET "/products/_search" '{
  "query": {
    "multi_match": {
      "query": "wireless noise",
      "fields": ["name", "description"]
    }
  },
  "highlight": {
    "fields": {
      "name": {},
      "description": {
        "pre_tags": ["<mark>"],
        "post_tags": ["</mark>"],
        "fragment_size": 100,
        "number_of_fragments": 2
      }
    }
  }
}'

explain "Highlight with a different query than the search query"
run_es GET "/products/_search" '{
  "query": { "match": { "category": "Electronics" } },
  "highlight": {
    "fields": {
      "description": {
        "highlight_query": {
          "match": { "description": "battery wireless" }
        }
      }
    }
  }
}'

exam_tip "fragment_size = max characters per highlight snippet."
exam_tip "number_of_fragments = how many snippets to return."
exam_tip "type: 'unified' (default), 'plain', or 'fvh' (fast vector highlighter)."
pause_step

# ---- 8.2: SORTING ----
section "8.2 — Sorting Results"

explain "Sort by price ascending"
run_es GET "/products/_search" '{
  "query": { "match_all": {} },
  "sort": [
    { "price": "asc" }
  ],
  "_source": ["name", "price"]
}'

explain "Multi-field sort: category asc, then price desc"
run_es GET "/products/_search" '{
  "query": { "match_all": {} },
  "sort": [
    { "category": "asc" },
    { "price": "desc" }
  ],
  "_source": ["name", "category", "price"]
}'

explain "Sort by _score (relevance) first, then by date"
run_es GET "/products/_search" '{
  "query": { "match": { "description": "wireless" } },
  "sort": [
    "_score",
    { "created_at": "desc" }
  ],
  "_source": ["name", "created_at"]
}'

explain "Sort with missing values handling"
run_es GET "/products/_search" '{
  "query": { "match_all": {} },
  "sort": [
    { "rating": { "order": "desc", "missing": "_last" } }
  ],
  "_source": ["name", "rating"]
}'

exam_tip "You can only sort on keyword, numeric, date, or boolean fields."
exam_tip "Sorting on text fields requires a .keyword sub-field."
pause_step

# ---- 8.3: PAGINATION ----
section "8.3 — Pagination"

explain "Method 1: from/size (simple, limited to 10000 total)"
run_es GET "/products/_search" '{
  "from": 0,
  "size": 3,
  "query": { "match_all": {} },
  "sort": [{ "price": "asc" }],
  "_source": ["name", "price"]
}'

explain "Page 2:"
run_es GET "/products/_search" '{
  "from": 3,
  "size": 3,
  "query": { "match_all": {} },
  "sort": [{ "price": "asc" }],
  "_source": ["name", "price"]
}'

explain "Method 2: search_after (for deep pagination, no 10k limit)"
explain "Uses the sort values from the last document of previous page"
run_es GET "/products/_search" '{
  "size": 3,
  "query": { "match_all": {} },
  "sort": [
    { "price": "asc" },
    { "_id": "asc" }
  ],
  "_source": ["name", "price"]
}'

explain "Then use the last document sort values as search_after:"
explain "(Replace the values below with actual values from your results)"
run_es GET "/products/_search" '{
  "size": 3,
  "query": { "match_all": {} },
  "sort": [
    { "price": "asc" },
    { "_id": "asc" }
  ],
  "search_after": [39.99, "9"],
  "_source": ["name", "price"]
}'

explain "Method 3: scroll API (for processing all results — export/reindex)"
echo -e "${DIM}  POST /products/_search?scroll=1m  { \"size\": 5, \"query\": {\"match_all\":{}} }${NC}"
echo -e "${DIM}  → returns a scroll_id${NC}"
echo -e "${DIM}  POST /_search/scroll { \"scroll\": \"1m\", \"scroll_id\": \"...\" }${NC}"

exam_tip "from/size: simple but limited to 10,000 (index.max_result_window)."
exam_tip "search_after: efficient deep pagination, requires a sort with tiebreaker."
exam_tip "scroll: for batch export, not for real-time user pagination."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Search products for 'premium' and highlight matches in name and description with <strong> tags"
exercise "Sort weblogs by response_time_ms descending, then by @timestamp ascending"
exercise "Implement search_after pagination to page through all weblogs 5 at a time"

echo ""
echo -e "${GREEN}✅ Lab 08 Complete! Next: ./scripts/09-cluster-management.sh${NC}"
