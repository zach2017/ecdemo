#!/usr/bin/env bash
# =============================================================================
# 05 — Aggregations
# =============================================================================
# EXAM TOPICS:
#   "Write and execute metric and bucket aggregations"
#   "Write and execute aggregations that contain sub-aggregations"
#   "Write and execute pipeline aggregations"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 05: Aggregations                                      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 5.1: METRIC AGGREGATIONS ----
section "5.1 — Metric Aggregations"

explain "avg, sum, min, max, stats, cardinality, value_count"

run_es GET "/products/_search?size=0" '{
  "aggs": {
    "avg_price":       { "avg": { "field": "price" } },
    "max_price":       { "max": { "field": "price" } },
    "min_price":       { "min": { "field": "price" } },
    "total_sold":      { "sum": { "field": "sold_count" } },
    "price_stats":     { "stats": { "field": "price" } },
    "unique_brands":   { "cardinality": { "field": "brand" } },
    "price_percentiles": {
      "percentiles": { "field": "price", "percents": [25, 50, 75, 90, 99] }
    }
  }
}'

exam_tip "size=0 means return aggregation results only, no document hits."
exam_tip "cardinality is approximate (HyperLogLog) — great for unique counts."
pause_step

# ---- 5.2: BUCKET AGGREGATIONS ----
section "5.2 — Bucket Aggregations"

explain "terms — group by field values (like SQL GROUP BY)"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "by_category": {
      "terms": { "field": "category", "size": 10 }
    }
  }
}'

explain "range — custom numeric buckets"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "price_ranges": {
      "range": {
        "field": "price",
        "ranges": [
          { "key": "budget",  "to": 50 },
          { "key": "mid",     "from": 50, "to": 150 },
          { "key": "premium", "from": 150 }
        ]
      }
    }
  }
}'

explain "date_histogram — time-based buckets"
run_es GET "/weblogs/_search?size=0" '{
  "aggs": {
    "requests_over_time": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "minute"
      }
    }
  }
}'

explain "histogram — fixed-width numeric buckets"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "price_histogram": {
      "histogram": { "field": "price", "interval": 50 }
    }
  }
}'

explain "filter — single filter bucket"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "expensive_electronics": {
      "filter": {
        "bool": {
          "must": [
            { "term": { "category": "Electronics" } },
            { "range": { "price": { "gte": 100 } } }
          ]
        }
      },
      "aggs": {
        "avg_rating": { "avg": { "field": "rating" } }
      }
    }
  }
}'

pause_step

# ---- 5.3: SUB-AGGREGATIONS ----
section "5.3 — Sub-Aggregations (Nested Aggs)"

explain "Nest metric aggs inside bucket aggs for per-group statistics"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "by_category": {
      "terms": { "field": "category", "size": 10 },
      "aggs": {
        "avg_price":    { "avg": { "field": "price" } },
        "avg_rating":   { "avg": { "field": "rating" } },
        "total_sold":   { "sum": { "field": "sold_count" } },
        "top_product":  {
          "top_hits": {
            "size": 1,
            "_source": ["name", "price", "rating"],
            "sort": [{ "rating": "desc" }]
          }
        }
      }
    }
  }
}'

explain "Multi-level nesting: category → brand → stats"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "by_category": {
      "terms": { "field": "category" },
      "aggs": {
        "by_brand": {
          "terms": { "field": "brand" },
          "aggs": {
            "price_stats": { "stats": { "field": "price" } }
          }
        }
      }
    }
  }
}'

explain "Weblog aggregation: status codes by server, with avg response time"
run_es GET "/weblogs/_search?size=0" '{
  "aggs": {
    "by_server": {
      "terms": { "field": "server" },
      "aggs": {
        "by_status": {
          "terms": { "field": "status_code" },
          "aggs": {
            "avg_response": { "avg": { "field": "response_time_ms" } }
          }
        },
        "total_bytes": { "sum": { "field": "bytes_sent" } }
      }
    }
  }
}'

pause_step

# ---- 5.4: PIPELINE AGGREGATIONS ----
section "5.4 — Pipeline Aggregations"

explain "Pipeline aggs operate on the output of other aggregations."
explain "cumulative_sum — running total across buckets"

run_es GET "/weblogs/_search?size=0" '{
  "aggs": {
    "requests_per_minute": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "minute"
      },
      "aggs": {
        "total_bytes": {
          "sum": { "field": "bytes_sent" }
        },
        "cumulative_bytes": {
          "cumulative_sum": { "buckets_path": "total_bytes" }
        }
      }
    }
  }
}'

explain "max_bucket — which category has the highest average price?"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "by_category": {
      "terms": { "field": "category" },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } }
      }
    },
    "most_expensive_category": {
      "max_bucket": { "buckets_path": "by_category>avg_price" }
    }
  }
}'

explain "avg_bucket — average of all category averages"
run_es GET "/products/_search?size=0" '{
  "aggs": {
    "by_category": {
      "terms": { "field": "category" },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } }
      }
    },
    "overall_avg_of_avgs": {
      "avg_bucket": { "buckets_path": "by_category>avg_price" }
    }
  }
}'

exam_tip "buckets_path uses > to navigate: 'parent_agg>child_agg'"
exam_tip "Pipeline aggs: derivative, cumulative_sum, moving_avg, avg_bucket,"
exam_tip "  max_bucket, min_bucket, sum_bucket, stats_bucket, bucket_sort"
exam_tip "bucket_sort can sort and paginate aggregation buckets."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Find the average response_time_ms grouped by HTTP method in weblogs"
exercise "Calculate the 50th and 95th percentile of response_time_ms"
exercise "Create a date_histogram per minute with sub-agg for avg response_time, then add a derivative pipeline agg to see the rate of change"
exercise "Use bucket_sort to get only the top 3 categories by total sold_count"

echo ""
echo -e "${GREEN}✅ Lab 05 Complete! Next: ./scripts/06-ingest-pipelines.sh${NC}"
