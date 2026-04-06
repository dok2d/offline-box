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

# Initialize database on first run
if ! su -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='bigbluebutton'\"" postgres | grep -q 1; then
  su -c "psql --command \"CREATE USER bigbluebutton WITH PASSWORD '${BBB_DB_PASSWORD:-changeme}';\"" postgres
  su -c "createdb -O bigbluebutton bigbluebutton" postgres
  echo "PostgreSQL database initialized."
fi

# Start FreeSWITCH
freeswitch -nc -nonat -nf -nosql \
  -rp \
  -conf /etc/freeswitch \
  -log /var/log/freeswitch \
  -run /var/run/freeswitch \
  -db /var/lib/freeswitch/db
echo "FreeSWITCH started."

# Start bbb-web directly on the published port
if [ -f /app/bbb-web/bbb-web.war ]; then
  cd /app/bbb-web
  exec java -Xmx256m -Xms128m \
    -Dbigbluebutton.properties=/etc/bigbluebutton/bigbluebutton.properties \
    -Dserver.port=8013 \
    -Dserver.servlet.context-path=/bbb \
    -jar bbb-web.war
else
  echo "ERROR: bbb-web.war not found"
  exit 1
fi
