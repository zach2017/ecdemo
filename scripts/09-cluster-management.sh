#!/usr/bin/env bash
# =============================================================================
# 09 — Cluster Management
# =============================================================================
# EXAM TOPICS:
#   "Diagnose shard issues and fix cluster health"
#   "Configure shard allocation awareness/filtering"
#   "Set up snapshot repository and take/restore snapshots"
#   "Manage cluster settings"
# =============================================================================
source "$(dirname "$0")/_helpers.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Lab 09: Cluster Management                                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ---- 9.1: CLUSTER HEALTH ----
section "9.1 — Cluster Health & Diagnostics"

explain "Cluster health: green = all good, yellow = replicas missing, red = data missing"
run_es GET "/_cluster/health"

explain "Node information"
run_es GET "/_cat/nodes?v&h=name,role,heap.percent,cpu,load_1m,disk.used_percent,node.attr.zone"

explain "Index overview"
run_es GET "/_cat/indices?v&s=index"

explain "Shard allocation detail"
run_es GET "/_cat/shards?v&s=index"

explain "Why is a shard unassigned? (if any exist)"
run_es GET "/_cluster/allocation/explain" '{
  "index": "products",
  "shard": 0,
  "primary": false
}'

pause_step

# ---- 9.2: CLUSTER SETTINGS ----
section "9.2 — Cluster Settings (Transient vs Persistent)"

explain "Transient = survives cluster restart? NO. Persistent = YES."
explain "Transient overrides persistent during runtime."

explain "View current settings"
run_es GET "/_cluster/settings?include_defaults=false&flat_settings=true"

explain "Set a persistent setting — allocation awareness by zone"
run_es PUT "/_cluster/settings" '{
  "persistent": {
    "cluster.routing.allocation.awareness.attributes": "zone"
  }
}'

explain "Set a transient setting — disable shard allocation temporarily"
explain "(Useful during node maintenance)"
run_es PUT "/_cluster/settings" '{
  "transient": {
    "cluster.routing.allocation.enable": "primaries"
  }
}'

explain "Re-enable full allocation"
run_es PUT "/_cluster/settings" '{
  "transient": {
    "cluster.routing.allocation.enable": "all"
  }
}'

exam_tip "allocation.enable values: all, primaries, new_primaries, none"
exam_tip "Set to 'none' before node maintenance, 'all' after."
pause_step

# ---- 9.3: SHARD ALLOCATION FILTERING ----
section "9.3 — Shard Allocation Filtering"

explain "Force an index to specific nodes using node attributes."
explain "Our nodes have: es01 (zone=zone-a, temp=hot), es02 (zone=zone-b, temp=warm)"

explain "Move products index to only 'hot' nodes"
run_es PUT "/products/_settings" '{
  "index.routing.allocation.include.temp": "hot"
}'

explain "Check where shards moved"
run_es GET "/_cat/shards/products?v&h=index,shard,prirep,state,node"

explain "Allow products on both hot and warm"
run_es PUT "/products/_settings" '{
  "index.routing.allocation.include.temp": "hot,warm"
}'

explain "Exclude a node (useful for decommissioning)"
run_es PUT "/products/_settings" '{
  "index.routing.allocation.exclude._name": "es02"
}'

explain "Clear the exclusion"
run_es PUT "/products/_settings" '{
  "index.routing.allocation.exclude._name": null
}'

exam_tip "include = shard CAN go to nodes with this attribute"
exam_tip "exclude = shard CANNOT go to nodes with this attribute"
exam_tip "require = shard MUST go to nodes with this attribute"
pause_step

# ---- 9.4: SNAPSHOTS & RESTORE ----
section "9.4 — Snapshots & Restore"

explain "The snapshot repo 'exam-backups' was registered during setup."
run_es GET "/_snapshot/exam-backups"

explain "Take a snapshot of all indices"
run_es PUT "/_snapshot/exam-backups/snapshot-1?wait_for_completion=true" '{
  "indices": "products,weblogs,suppliers",
  "include_global_state": false
}'

explain "List snapshots"
run_es GET "/_snapshot/exam-backups/_all"

explain "Take a snapshot of just one index"
run_es PUT "/_snapshot/exam-backups/products-only?wait_for_completion=true" '{
  "indices": "products",
  "include_global_state": false
}'

explain "Delete the products index (to test restore)"
run_es DELETE "/products-restore-test" 2>/dev/null
echo ""

explain "Restore from snapshot into a different index name"
run_es POST "/_snapshot/exam-backups/products-only/_restore" '{
  "indices": "products",
  "rename_pattern": "products",
  "rename_replacement": "products-restore-test",
  "include_global_state": false
}'

explain "Verify the restore"
run_es GET "/products-restore-test/_count"

explain "Clean up"
run_es DELETE "/products-restore-test"

exam_tip "You CANNOT restore into an existing open index. Close or delete it first."
exam_tip "rename_pattern/rename_replacement let you restore with a new name."
exam_tip "include_global_state: false is safer — avoids overwriting cluster settings."

# ---- EXERCISES ----
section "EXERCISES"

exercise "Create a snapshot containing only weblogs, then delete weblogs, restore it"
exercise "Use allocation filtering to move weblogs to only 'warm' nodes, verify with _cat/shards"
exercise "Set the cluster so that primary and replica of the same shard are never on the same zone"

echo ""
echo -e "${GREEN}✅ Lab 09 Complete! Next: ./scripts/10-security.sh${NC}"
