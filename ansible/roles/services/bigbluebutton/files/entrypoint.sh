#!/bin/bash
set -e

echo "Starting BigBlueButton services..."

# Start Redis
redis-server --daemonize yes --port 6379 --bind 127.0.0.1 --dir /run/redis
for i in $(seq 1 30); do
  redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1 && break
  sleep 0.5
done
echo "Redis started."

# Start PostgreSQL
su -c "/usr/lib/postgresql/*/bin/pg_ctl -D /var/lib/postgresql/*/main start -l /var/log/postgresql/startup.log -w" postgres
echo "PostgreSQL started."

# Start FreeSWITCH
freeswitch -nc -nonat -nf -nosql \
  -rp \
  -conf /etc/freeswitch \
  -log /var/log/freeswitch \
  -run /var/run/freeswitch \
  -db /var/lib/freeswitch/db || true
echo "FreeSWITCH started."

# Start internal nginx for BBB
cat > /etc/nginx/sites-enabled/bbb.conf << 'NGINX'
server {
    listen 8013 default_server;

    location /bbb/api {
        proxy_pass http://127.0.0.1:8090/bbb/api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /bbb/html5client {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location /bbb/ {
        alias /app/bbb-web/;
        index index.html;
        try_files $uri $uri/ /bbb/api;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
nginx
echo "Internal nginx started."

# Start bbb-web (Grails application)
if [ -f /app/bbb-web/bbb-web.war ]; then
  cd /app/bbb-web
  java -Xmx256m -Xms128m \
    -Dbigbluebutton.properties=/etc/bigbluebutton/bigbluebutton.properties \
    -Dserver.port=8090 \
    -Dserver.servlet.context-path=/bbb \
    -jar bbb-web.war &
  echo "bbb-web started."
fi

echo "BigBlueButton is running."

# Keep container alive — wait for any process to exit
wait -n || true

# Fallback: keep alive
tail -f /var/log/bigbluebutton/*.log /var/log/nginx/*.log 2>/dev/null || sleep infinity
