#!/usr/bin/env bash
ES="http://localhost:9200"
PASS="${ELASTIC_PASSWORD:-examlab2026}"
AUTH="elastic:${PASS}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

run_es() {
  local METHOD="$1"
  local ENDPOINT="$2"
  local BODY="${3:-}"

  echo ""
  echo -e "${DIM}───────────────────────────────────────────────${NC}"
  echo -e "${BOLD}${METHOD} ${ENDPOINT}${NC}"
  [[ -n "$BODY" ]] && echo -e "${DIM}${BODY}${NC}"
  echo ""

  if [[ -n "$BODY" ]]; then
    curl -s -u "$AUTH" -X "$METHOD" "${ES}${ENDPOINT}" \
      -H 'Content-Type: application/json' -d "$BODY" | python3 -m json.tool 2>/dev/null || \
    curl -s -u "$AUTH" -X "$METHOD" "${ES}${ENDPOINT}" \
      -H 'Content-Type: application/json' -d "$BODY"
  else
    curl -s -u "$AUTH" -X "$METHOD" "${ES}${ENDPOINT}" | python3 -m json.tool 2>/dev/null || \
    curl -s -u "$AUTH" -X "$METHOD" "${ES}${ENDPOINT}"
  fi
  echo ""
}

section()    { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${CYAN}  $1${NC}\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
explain()    { echo -e "${GREEN}  ✦ $1${NC}"; }
exam_tip()   { echo -e "${YELLOW}  🎓 EXAM TIP: $1${NC}"; }
exercise()   { echo -e "\n${RED}  ✏️  TRY IT YOURSELF: $1${NC}\n${DIM}     (Kibana Dev Tools → http://localhost:5601  login: elastic / ${PASS})${NC}"; }
pause_step() { echo -e "\n${DIM}  Press ENTER to continue...${NC}"; read -r; }
