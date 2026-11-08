#!/bin/bash
# Railway entrypoint for OpenSourcePOS 3.4.3. Runs as root, hands Apache to the upstream CMD.
set -euo pipefail

APP=/app
DATA=/data
PORT="${PORT:-8080}"
log() { echo "[railway] $*"; }

# --- one Apache MPM, listening on Railway's PORT -----------------------------------------------------------------
# Railway ignores OCI whiteouts, so mpm_event can come back beside mpm_prefork ("AH00534: More than one MPM loaded").
a2dismod -f mpm_event mpm_worker >/dev/null 2>&1 || true
a2enmod mpm_prefork rewrite >/dev/null 2>&1 || true
sed -ri "s/^Listen[[:space:]]+[0-9]+/Listen ${PORT}/" /etc/apache2/ports.conf
for vhost in /etc/apache2/sites-available/*.conf; do
  sed -ri "s#<VirtualHost \*:[0-9]+>#<VirtualHost *:${PORT}>#" "$vhost"
done
cat > /etc/apache2/conf-enabled/railway.conf <<'CONF'
ServerName localhost
SetEnvIf X-Forwarded-Proto "^https$" HTTPS=on
CONF

# --- required secrets --------------------------------------------------------------------------------------------
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  echo "[railway] ADMIN_PASSWORD is empty -- refusing to boot with the published default login" >&2
  exit 1
fi
if [ -z "${MYSQL_HOST_NAME:-}" ] || [ -z "${MYSQL_PASSWORD:-}" ]; then
  echo "[railway] MYSQL_HOST_NAME / MYSQL_PASSWORD missing" >&2
  exit 1
fi
export ALLOWED_HOSTNAMES="${ALLOWED_HOSTNAMES:-${RAILWAY_PUBLIC_DOMAIN:-localhost}}"

# --- volume: keys and uploads ------------------------------------------------------------------------------------
mkdir -p "$DATA/uploads"
if [ ! -L "$APP/public/uploads" ]; then
  if [ -z "$(ls -A "$DATA/uploads" 2>/dev/null)" ]; then cp -a "$APP/public/uploads/." "$DATA/uploads/"; fi
  rm -rf "$APP/public/uploads"
  ln -s "$DATA/uploads" "$APP/public/uploads"
fi
chown -R www-data:www-data "$DATA/uploads"
chmod 750 "$DATA/uploads"

# --- database ----------------------------------------------------------------------------------------------------
log "waiting for database"
attempt=0
until php -r '
  mysqli_report(MYSQLI_REPORT_OFF);
  $c = @mysqli_connect(getenv("MYSQL_HOST_NAME"), getenv("MYSQL_USERNAME"), getenv("MYSQL_PASSWORD"), getenv("MYSQL_DB_NAME"));
  exit($c ? 0 : 1);
' >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then echo "[railway] database never became reachable" >&2; exit 1; fi
  sleep 3
done

# --- schema ---
log "running migrations"
(cd "$APP" && php spark migrate --all -n)

# env:provision reads the app_config table, so it runs after the migrations create it (fresh database).
# .env holds encryption.key and throttle.key. Losing it makes stored secrets unreadable, so it lives on the volume.
if [ -s "$DATA/.env" ]; then
  cp "$DATA/.env" "$APP/.env"
elif [ -f "$APP/.env.example" ]; then
  cp "$APP/.env.example" "$APP/.env"
else
  : > "$APP/.env"
fi
log "provisioning keys"
(cd "$APP" && php spark env:provision)
# Railway's edge address rotates per request, so a session bound to the client IP (matchIP defaults to true)
# logs the user out on the next click. Same trap as sftpgo; turn the binding off.
if ! grep -q '^session.matchIP' "$APP/.env"; then
  printf '\nsession.matchIP = false\n' >> "$APP/.env"
fi
cp "$APP/.env" "$DATA/.env"
chmod 600 "$DATA/.env"
chown root:www-data "$APP/.env"
chmod 640 "$APP/.env"

# --- admin password ----------------------------------------------------------------------------------------------
# Replace the published default only while it is still the default, so a password the owner changed in the UI sticks.
php -r '
  mysqli_report(MYSQLI_REPORT_OFF);
  $c = mysqli_connect(getenv("MYSQL_HOST_NAME"), getenv("MYSQL_USERNAME"), getenv("MYSQL_PASSWORD"), getenv("MYSQL_DB_NAME"));
  if (!$c) { fwrite(STDERR, "[railway] admin bootstrap: connect failed\n"); exit(1); }
  $r = mysqli_query($c, "SELECT password, hash_version FROM ospos_employees WHERE username = \"admin\"");
  $row = $r ? mysqli_fetch_assoc($r) : null;
  if (!$row) { echo "[railway] no admin row, leaving accounts alone\n"; exit(0); }
  $isDefault = ($row["hash_version"] === "1" && $row["password"] === md5("pointofsale"))
            || ($row["hash_version"] === "2" && password_verify("pointofsale", $row["password"]));
  if (!$isDefault) { echo "[railway] admin password already set, leaving it\n"; exit(0); }
  $h = password_hash(getenv("ADMIN_PASSWORD"), PASSWORD_DEFAULT);
  $s = mysqli_prepare($c, "UPDATE ospos_employees SET password = ?, hash_version = 2 WHERE username = \"admin\"");
  mysqli_stmt_bind_param($s, "s", $h);
  if (!mysqli_stmt_execute($s)) { fwrite(STDERR, "[railway] admin bootstrap failed\n"); exit(1); }
  echo "[railway] admin password set from ADMIN_PASSWORD\n";
'

exec docker-php-entrypoint "$@"
