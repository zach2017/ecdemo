#!/usr/bin/env bash
# =============================================================================
# 01 — Index Management
# =============================================================================
# EXAM TOPIC: Data Management
#   "Define an index that satisfies a given set of requirements"
#
# Skills practiced:
#   ✓ Create indices with custom settings and mappings
#   ✓ Configure shard count, replicas, and aliases
#   ✓ Define explicit field mappings with different data types
#   ✓ Use multi-fields (text + keyword)
#   ✓ Configure analyzers and field parameters
#   ✓ Perform CRUD operations on documents
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 01: Index Management                                  ║${NC}"
echo -e "${CYAN}║   Exam Topic: Data Management                               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 1.1: CREATE AN INDEX WITH SETTINGS & MAPPINGS ----
section "1.1 — Create an Index with Custom Settings and Mappings"

explain "We create an index called 'blog-posts' with 2 primary shards,"
explain "1 replica, and explicit mappings for each field."
explain "Notice how 'title' has a multi-field: text for search + keyword for sorting."

run_es PUT "/blog-posts" '{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1,
    "analysis": {
      "analyzer": {
        "english_custom": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "english_stemmer"]
        }
      },
      "filter": {
        "english_stemmer": {
          "type": "stemmer",
          "language": "english"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title":       {"type": "text", "analyzer": "english_custom",
                      "fields": {"keyword": {"type": "keyword"}}},
      "body":        {"type": "text", "analyzer": "english_custom"},
      "author":      {"type": "keyword"},
      "tags":        {"type": "keyword"},
      "published":   {"type": "date", "format": "yyyy-MM-dd||epoch_millis"},
      "views":       {"type": "integer"},
      "is_featured": {"type": "boolean"},
      "location":    {"type": "geo_point"},
      "comments": {
        "type": "nested",
        "properties": {
          "user":    {"type": "keyword"},
          "text":    {"type": "text"},
          "date":    {"type": "date"}
        }
      }
    }
  },
  "aliases": {
    "blog": {},
    "featured-posts": {
      "filter": {"term": {"is_featured": true}}
    }
  }
}'

exam_tip "You CANNOT change number_of_shards after creation. Plan ahead!"
exam_tip "Aliases with filters (like 'featured-posts' above) are common exam tasks."
pause_step

# ---- 1.2: INDEX DOCUMENTS ----
section "1.2 — Index Documents (CRUD Operations)"

explain "Index a document with auto-generated ID (POST)"
run_es POST "/blog-posts/_doc" '{
  "title": "Getting Started with Elasticsearch",
  "body": "Elasticsearch is a distributed search engine built on Apache Lucene...",
  "author": "jane_doe",
  "tags": ["elasticsearch", "tutorial", "beginner"],
  "published": "2026-03-15",
  "views": 1520,
  "is_featured": true,
  "location": {"lat": 40.7128, "lon": -74.0060},
  "comments": [
    {"user": "bob", "text": "Great article!", "date": "2026-03-16"},
    {"user": "alice", "text": "Very helpful, thanks", "date": "2026-03-17"}
  ]
}'

explain "Index a document with explicit ID (PUT)"
run_es PUT "/blog-posts/_doc/post-100" '{
  "title": "Advanced Aggregations in Elasticsearch",
  "body": "Pipeline aggregations allow you to compute derivatives and moving averages...",
  "author": "john_smith",
  "tags": ["elasticsearch", "aggregations", "advanced"],
  "published": "2026-03-20",
  "views": 870,
  "is_featured": false,
  "location": {"lat": 51.5074, "lon": -0.1278}
}'

explain "Index more documents for richer search results"
run_es POST "/blog-posts/_bulk" '
{"index":{"_id":"post-101"}}
{"title":"Kubernetes for Beginners","body":"Kubernetes orchestrates containerized applications across a cluster of machines...","author":"jane_doe","tags":["kubernetes","containers","devops"],"published":"2026-02-10","views":3200,"is_featured":true}
{"index":{"_id":"post-102"}}
{"title":"Ingest Pipelines Deep Dive","body":"Ingest pipelines process documents before indexing using a series of processors...","author":"john_smith","tags":["elasticsearch","ingest","pipelines"],"published":"2026-03-25","views":445,"is_featured":false}
{"index":{"_id":"post-103"}}
{"title":"Monitoring Elasticsearch Clusters","body":"Cluster health monitoring is essential for production Elasticsearch deployments...","author":"admin_user","tags":["elasticsearch","monitoring","operations"],"published":"2026-01-05","views":2100,"is_featured":true}
{"index":{"_id":"post-104"}}
{"title":"Docker Compose for Local Development","body":"Docker Compose simplifies multi-container application setups for development...","author":"jane_doe","tags":["docker","containers","development"],"published":"2026-03-01","views":1750,"is_featured":false}
'

pause_step

# ---- 1.3: READ / GET DOCUMENTS ----
section "1.3 — Retrieve Documents"

explain "Get a specific document by ID"
run_es GET "/blog-posts/_doc/post-100"

explain "Check if a document exists (HEAD request returns status code only)"
echo -e "${DIM}HEAD /blog-posts/_doc/post-100${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" -X HEAD "$ES/blog-posts/_doc/post-100")
echo -e "  HTTP Status: ${GREEN}${HTTP_CODE}${NC} (200 = exists, 404 = not found)"

explain "Get multiple documents at once with _mget"
run_es POST "/blog-posts/_mget" '{
  "ids": ["post-100", "post-101", "post-103"]
}'

pause_step

# ---- 1.4: UPDATE DOCUMENTS ----
section "1.4 — Update Documents"

explain "Partial update (only changes specified fields)"
run_es POST "/blog-posts/_update/post-100" '{
  "doc": {
    "views": 950,
    "tags": ["elasticsearch", "aggregations", "advanced", "exam-prep"]
  }
}'

explain "Scripted update (increment views by 100)"
run_es POST "/blog-posts/_update/post-100" '{
  "script": {
    "source": "ctx._source.views += params.count",
    "params": { "count": 100 }
  }
}'

explain "Verify the update"
run_es GET "/blog-posts/_doc/post-100?_source_includes=title,views,tags"

pause_step

# ---- 1.5: DELETE OPERATIONS ----
section "1.5 — Delete Documents and Indices"

explain "Delete a single document"
run_es DELETE "/blog-posts/_doc/post-104"

explain "Delete by query (delete all posts with views < 500)"
run_es POST "/blog-posts/_delete_by_query" '{
  "query": {
    "range": { "views": { "lt": 500 } }
  }
}'

explain "Check what remains"
run_es GET "/blog-posts/_count"

pause_step

# ---- 1.6: CHECK MAPPINGS & SETTINGS ----
section "1.6 — Inspect Index Mappings and Settings"

explain "View the mapping for an index"
run_es GET "/blog-posts/_mapping"

explain "View the settings for an index"
run_es GET "/blog-posts/_settings"

explain "Use the alias to query"
run_es GET "/blog/_count"

exam_tip "Know how to read and write mappings from scratch. The exam will ask"
exam_tip "you to create indices with very specific field types and settings."

# ---- EXERCISES ----
section "EXERCISES — Try These in Kibana Dev Tools"

exercise "Create an index called 'movies' with fields: title (text+keyword), director (keyword), year (integer), rating (float), genres (keyword array), release_date (date)"
exercise "Add 5 movie documents using _bulk API"
exercise "Create a filtered alias called 'top-movies' that only includes movies with rating > 8.0"
exercise "Update all movies from 2025 to add a tag 'recent' using _update_by_query"

echo ""
echo -e "${GREEN}✅ Lab 01 Complete! Next: ./scripts/02-index-templates.sh${NC}"
