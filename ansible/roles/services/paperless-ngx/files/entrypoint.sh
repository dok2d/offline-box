#!/bin/bash
set -e
redis-server --daemonize yes --port 6379 --bind 127.0.0.1 --dir /run/redis
cd /app
/app/venv/bin/celery -A paperless worker -l info --detach
exec /app/venv/bin/gunicorn -b 0.0.0.0:8012 paperless.asgi:application -k uvicorn.workers.UvicornWorker
