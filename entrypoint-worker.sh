#!/bin/bash
set -e

echo "Waiting for OpenBench server to respond at $SERVER_URL..."
until curl -s --connect-timeout 5 "$SERVER_URL" > /dev/null; do
  echo "OpenBench server is not reachable yet, waiting..."
  sleep 3
done
echo "OpenBench server is online!"

# Set up the worker code directory
WORKER_DIR="/worker/app"

if [ ! -d "$WORKER_DIR/.git" ]; then
  echo "Cloning OpenBench fork from $OPENBENCH_REPO (branch: $OPENBENCH_REF)..."
  git clone --branch "$OPENBENCH_REF" "$OPENBENCH_REPO" "$WORKER_DIR"
else
  echo "Worker directory exists. Pulling latest code..."
  cd "$WORKER_DIR"
  git remote set-url origin "$OPENBENCH_REPO"
  git fetch origin
  git checkout "$OPENBENCH_REF"
  git pull origin "$OPENBENCH_REF"
fi

cd "$WORKER_DIR"

# Install client packages if requirements.txt exists
if [ -f "requirements.txt" ]; then
  echo "Installing client dependencies..."
  pip install --no-cache-dir --break-system-packages -r requirements.txt
fi

echo "===================================================================="
echo "Starting OpenBench Client with settings:"
echo "Server URL : $SERVER_URL"
echo "Worker User: $WORKER_USER"
echo "Threads    : $WORKER_THREADS"
echo "===================================================================="

# Run the OpenBench client. Use exec so SIGTERM/SIGINT signals from docker-compose
# are handled gracefully by the python process.
exec python3 Client/client.py -U "$WORKER_USER" -P "$WORKER_PASSWORD" -S "$SERVER_URL" -T "$WORKER_THREADS" -N 1
