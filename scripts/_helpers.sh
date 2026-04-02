#!/usr/bin/env bash
# Shared variables and helpers — insecure dev mode (no auth)
ES="http://localhost:9200"

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

  if [[ -n "$BODY" ]]; then
    echo -e "${DIM}${BODY}${NC}"
  fi

  echo ""

  if [[ -n "$BODY" ]]; then
    curl -s -X "$METHOD" "${ES}${ENDPOINT}" \
      -H 'Content-Type: application/json' \
      -d "$BODY" | python3 -m json.tool 2>/dev/null || \
    curl -s -X "$METHOD" "${ES}${ENDPOINT}" \
      -H 'Content-Type: application/json' \
      -d "$BODY"
  else
    curl -s -X "$METHOD" "${ES}${ENDPOINT}" | python3 -m json.tool 2>/dev/null || \
    curl -s -X "$METHOD" "${ES}${ENDPOINT}"
  fi
  echo ""
}

section() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

explain() {
  echo -e "${GREEN}  ✦ $1${NC}"
}

exam_tip() {
  echo -e "${YELLOW}  🎓 EXAM TIP: $1${NC}"
}

exercise() {
  echo ""
  echo -e "${RED}  ✏️  TRY IT YOURSELF: $1${NC}"
  echo -e "${DIM}     (Open Kibana Dev Tools at http://localhost:5601 and try this)${NC}"
}

pause_step() {
  echo ""
  echo -e "${DIM}  Press ENTER to continue to the next section...${NC}"
  read -r
}
