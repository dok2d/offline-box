#!/bin/bash
set -e
redis-server --daemonize yes --port 6379 --bind 127.0.0.1 --dir /run/redis

# Wait for Redis to be ready
for i in $(seq 1 30); do
  redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1 && break
  sleep 0.5
done

cd /app
/app/venv/bin/celery -A paperless worker -l info --detach
exec /app/venv/bin/gunicorn -b 0.0.0.0:8012 paperless.asgi:application -k uvicorn.workers.UvicornWorker
