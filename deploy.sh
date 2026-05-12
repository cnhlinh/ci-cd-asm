# Usage: bash deploy.sh <image>   e.g. ghcr.io/org/repo:sha-abc1234
set -euo pipefail

IMAGE="${1:?Usage: deploy.sh <image>}"
CONTAINER_NAME="${CONTAINER_NAME:-app}"
HOST_PORT="${PORT:-8000}"
HEALTH_URL="http://localhost:${HOST_PORT}/health"
MAX_RETRIES=12
RETRY_INTERVAL=5

log()  { echo "[$(date -u +%H:%M:%SZ)] $*"; }
fail() { log "ERROR: $*"; exit 1; }

# ── Pull ──────────────────────────────────────────────────────────────────
log "Pulling image: $IMAGE"
docker pull "$IMAGE" || fail "Failed to pull image"

# ── Swap container ────────────────────────────────────────────────────────
log "Stopping existing container (if any)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm   "$CONTAINER_NAME" 2>/dev/null || true

log "Starting new container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${HOST_PORT}:8000" \
  "$IMAGE" || fail "docker run failed"

# ── Health check ──────────────────────────────────────────────────────────
log "Waiting for health endpoint: $HEALTH_URL"
for i in $(seq 1 "$MAX_RETRIES"); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    log "Health check passed (HTTP $STATUS)"
    break
  fi
  log "Attempt $i/$MAX_RETRIES — HTTP $STATUS, retrying in ${RETRY_INTERVAL}s..."
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    log "Health check failed — rolling back"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
    fail "Deployment rolled back after $MAX_RETRIES failed health checks"
  fi
  sleep "$RETRY_INTERVAL"
done

# ── Report ────────────────────────────────────────────────────────────────
log "Deployment successful"
log "  Image:     $IMAGE"
log "  Container: $CONTAINER_NAME"
log "  Port:      $HOST_PORT"
