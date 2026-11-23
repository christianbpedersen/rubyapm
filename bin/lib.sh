# Shared helpers for bin/ scripts.

# Stops whatever listens on TCP port $1 (graceful, then SIGKILL after 60s).
stop_port() {
  local port=$1 pids
  pids=$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u)
  [[ -z $pids ]] && return 0
  kill $pids 2>/dev/null || true
  for _ in $(seq 1 120); do
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  echo "port $port did not shut down gracefully; killing" >&2
  pkill -9 -P "$(echo $pids | tr ' ' ',')" 2>/dev/null || true
  kill -9 $pids 2>/dev/null || true
  sleep 1
  ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}
