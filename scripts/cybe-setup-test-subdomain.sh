#!/usr/bin/env bash
# Run on the cybe server (the one hosting nginx on :8443 TLS + k3s).
#
# What this does:
#   1. Reports current state (DNS, ports, existing vhosts, cert paths)
#   2. Writes /etc/nginx/sites-available/test.school.cybe.tech with the
#      cert path COPIED from whatever grafana.cybe.tech currently uses
#      (so we don't guess wrong)
#   3. Symlinks into sites-enabled
#   4. Validates nginx config
#   5. Reloads nginx
#   6. Smoke-tests the endpoint locally on the host
#
# Safe to re-run — uses `ln -sf` and `tee` (idempotent writes).

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║ test.school.cybe.tech nginx vhost setup                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "── 1. Existing working vhosts (source of truth for cert paths) ──"
ls /etc/nginx/sites-enabled/ | head -20
echo

echo "── 2. Borrow cert paths from grafana.cybe.tech ──"
if [ ! -f /etc/nginx/sites-available/grafana.cybe.tech ]; then
  echo "❌ grafana.cybe.tech vhost not found — aborting so you can manually"
  echo "   choose the cert path. List with: ls /etc/letsencrypt/live/"
  exit 1
fi

CERT=$(grep -E '^\s*ssl_certificate\s' /etc/nginx/sites-available/grafana.cybe.tech | head -1 | awk '{print $2}' | tr -d ';')
KEY=$(grep -E '^\s*ssl_certificate_key\s' /etc/nginx/sites-available/grafana.cybe.tech | head -1 | awk '{print $2}' | tr -d ';')

if [ -z "$CERT" ] || [ -z "$KEY" ]; then
  echo "❌ Could not extract cert paths from grafana vhost."
  echo "   Paste ssl_certificate / ssl_certificate_key lines from"
  echo "   /etc/nginx/sites-available/grafana.cybe.tech and re-run."
  exit 1
fi

echo "  cert: $CERT"
echo "  key : $KEY"
[ -f "$CERT" ] && echo "  ✅ cert file exists" || { echo "  ❌ cert file missing at $CERT"; exit 1; }
[ -f "$KEY" ]  && echo "  ✅ key file exists"  || { echo "  ❌ key file missing at $KEY"; exit 1; }
echo

echo "── 3. Writing /etc/nginx/sites-available/test.school.cybe.tech ──"
sudo tee /etc/nginx/sites-available/test.school.cybe.tech > /dev/null <<EOF
server {
    listen 8443 ssl http2;
    server_name test.school.cybe.tech;

    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options           SAMEORIGIN         always;
    add_header X-Content-Type-Options    nosniff            always;

    location / {
        proxy_pass http://127.0.0.1:32118;
        proxy_set_header Host              test.school.cybe.tech;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;

        # Next.js streaming + any websocket upgrade
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 60s;
        client_max_body_size 10m;
    }
}
EOF
echo "  ✅ written"
echo

echo "── 4. Enabling vhost ──"
sudo ln -sf /etc/nginx/sites-available/test.school.cybe.tech \
            /etc/nginx/sites-enabled/test.school.cybe.tech
ls -la /etc/nginx/sites-enabled/test.school.cybe.tech
echo

echo "── 5. nginx -t ──"
sudo nginx -t
echo

echo "── 6. Reload nginx ──"
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager | head -4
echo

echo "── 7. Smoke test (localhost → nginx :8443 → Traefik :32118 → Ingress) ──"
# --resolve maps the hostname to 127.0.0.1 so nginx gets the right Host header
curl -sI --max-time 10 -k --resolve test.school.cybe.tech:8443:127.0.0.1 \
  https://test.school.cybe.tech:8443/ 2>&1 | head -6
echo

echo "── 8. Confirm Traefik is reachable (baseline) ──"
curl -sI --max-time 5 -H "Host: test.school.cybe.tech" \
  http://127.0.0.1:32118/ 2>&1 | head -3
echo

echo "╔════════════════════════════════════════════════════════════╗"
echo "║ Done. Test externally from your laptop:                    ║"
echo "║   curl -sI https://test.school.cybe.tech:8443/             ║"
echo "╚════════════════════════════════════════════════════════════╝"
