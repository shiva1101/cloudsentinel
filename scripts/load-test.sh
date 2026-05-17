#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CloudSentinel Load Test
# Usage: ./scripts/load-test.sh [TARGET_URL] [DURATION_SECONDS] [CONCURRENCY]
# Example: ./scripts/load-test.sh http://localhost:80 60 50
# ─────────────────────────────────────────────────────────────────────────────

TARGET="${1:-http://localhost:80}"
DURATION="${2:-60}"
CONCURRENCY="${3:-20}"

echo "╔══════════════════════════════════════════════════╗"
echo "║        CloudSentinel Load Test                   ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Target      : $TARGET"
echo "║  Duration    : ${DURATION}s"
echo "║  Concurrency : $CONCURRENCY"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Check dependencies
command -v ab  &>/dev/null || { echo "Installing apache2-utils..."; sudo apt-get install -y apache2-utils -q; }

echo "▶ Phase 1: Baseline (light load)"
ab -n 100 -c 5 -q "$TARGET/health" 2>&1 | grep -E "Requests|Time per|Transfer|Failed"

echo ""
echo "▶ Phase 2: Sustained load on main endpoint"
ab -n $((CONCURRENCY * 100)) -c "$CONCURRENCY" -t "$DURATION" -q "$TARGET/" 2>&1 | \
  grep -E "Requests|Time per|Transfer|Failed|Complete|Non-2xx"

echo ""
echo "▶ Phase 3: CPU stress via /load endpoint"
ab -n 50 -c 10 -q "$TARGET/load?intensity=5000000" 2>&1 | \
  grep -E "Requests|Time per|Failed"

echo ""
echo "▶ Phase 4: Check /metrics scrape"
curl -s "$TARGET/metrics" | grep -E "^http_requests_total|^http_request_duration"

echo ""
echo "✅ Load test complete. Check Grafana at http://localhost:3001 for results."
