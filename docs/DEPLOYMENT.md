# GastroCore — Deployment Guide

## Table of Contents

- [Infrastructure Overview](#infrastructure-overview)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [VPS Deployment (Production)](#vps-deployment-production)
- [Nginx Configuration](#nginx-configuration)
- [SSL / TLS with Certbot](#ssl--tls-with-certbot)
- [Environment Variables Reference](#environment-variables-reference)
- [Database Migrations](#database-migrations)
- [GitHub Pages (Online Ordering Demo)](#github-pages-online-ordering-demo)
- [Android Distribution](#android-distribution)
- [CI/CD Pipelines](#cicd-pipelines)
- [Monitoring & Logs](#monitoring--logs)
- [Backup & Restore](#backup--restore)
- [Updating](#updating)

---

## Infrastructure Overview

```
Internet
   │
   ▼
Nginx (443 HTTPS)
   │  TLS termination
   │  Reverse proxy → :8080
   ▼
Docker network
   ├── gastrocore-server:8080  (Go binary)
   ├── postgres:5432           (PostgreSQL 16)
   └── redis:6379              (Redis 7)
```

Minimum VPS specs: **2 vCPU, 2 GB RAM, 20 GB SSD** (Ubuntu 22.04 LTS recommended).

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker | 24+ | `curl -fsSL https://get.docker.com | sh` |
| Docker Compose | v2 | included with Docker Desktop / `apt install docker-compose-plugin` |
| Nginx | latest | `apt install nginx` |
| Certbot | latest | `apt install certbot python3-certbot-nginx` |
| Git | any | `apt install git` |

---

## Local Development

```bash
# Clone the repository
git clone https://github.com/gastrocore/restaurant.git
cd restaurant

# Copy example environment file
cp .env.example .env
# Edit .env — at minimum set JWT_SECRET

# Start the full stack
docker-compose up -d

# Check health
curl http://localhost:8080/health

# View logs
docker-compose logs -f gastrocore-server

# Stop
docker-compose down
```

### Connecting Flutter to local server

In `apps/pos/lib/core/di/providers.dart`, update `syncServerUrlProvider`:
```dart
final syncServerUrlProvider = Provider<String>((ref) => 'http://10.0.2.2:8080');
// 10.0.2.2 = Android emulator → host machine
// Use your LAN IP for real devices
```

---

## VPS Deployment (Production)

### 1. Provision the server

```bash
# SSH into your VPS
ssh root@your-server.com

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER

# Install Nginx + Certbot
apt install -y nginx certbot python3-certbot-nginx git
```

### 2. Clone the repository

```bash
git clone https://github.com/gastrocore/restaurant.git /opt/gastrocore
cd /opt/gastrocore
```

### 3. Configure environment variables

```bash
# Create production env file
cat > /opt/gastrocore/.env << 'EOF'
JWT_SECRET=<generate with: openssl rand -hex 64>
JWT_EXPIRY=24h
LICENSE_SIGNING_KEY=<your-ed25519-public-key-base64>
LOG_LEVEL=info
ENV=production
EOF

chmod 600 /opt/gastrocore/.env
```

Generate a secure `JWT_SECRET`:
```bash
openssl rand -hex 64
```

### 4. Build and start containers

```bash
cd /opt/gastrocore

# Build server image
docker-compose build gastrocore-server

# Start all services
docker-compose --env-file .env up -d

# Run migrations
docker-compose exec gastrocore-server /app/gastrocore-server migrate
# (or via the migrate command if built separately)

# Verify
docker-compose ps
curl http://localhost:8080/health
```

### 5. Configure systemd restart (optional)

```bash
# Create systemd service for auto-restart on reboot
cat > /etc/systemd/system/gastrocore.service << 'EOF'
[Unit]
Description=GastroCore Docker Compose
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=/opt/gastrocore
ExecStart=/usr/bin/docker compose --env-file .env up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl enable gastrocore
systemctl start gastrocore
```

---

## Nginx Configuration

### Basic reverse proxy

```nginx
# /etc/nginx/sites-available/gastrocore
server {
    listen 80;
    server_name api.your-restaurant.com;

    # Redirect HTTP → HTTPS (Certbot will add this)
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.your-restaurant.com;

    # SSL certificates (managed by Certbot)
    ssl_certificate     /etc/letsencrypt/live/api.your-restaurant.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.your-restaurant.com/privkey.pem;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy strict-origin-when-cross-origin;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # API proxy
    location /api/ {
        proxy_pass         http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
        proxy_connect_timeout 5s;
    }

    # WebSocket proxy (sync + KDS)
    location /ws/ {
        proxy_pass         http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_read_timeout 300s;  # Long timeout for WebSocket
    }

    # Health check (no auth needed)
    location /health {
        proxy_pass http://localhost:8080;
    }

    # OpenAPI docs
    location /docs {
        proxy_pass http://localhost:8080;
    }
}
```

```bash
# Enable the site
ln -s /etc/nginx/sites-available/gastrocore /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

---

## SSL / TLS with Certbot

```bash
# Obtain certificate
certbot --nginx -d api.your-restaurant.com

# Test auto-renewal
certbot renew --dry-run

# Certbot adds a cron job automatically; verify with:
systemctl status certbot.timer
```

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `PORT` | no | `8080` | HTTP listen port |
| `ENV` | no | `development` | `development` or `production` |
| `LOG_LEVEL` | no | `info` | `debug`, `info`, `warn`, `error` |
| `DATABASE_URL` | **yes** | — | PostgreSQL DSN |
| `JWT_SECRET` | **yes** | — | HMAC secret for JWT signing (min 32 chars) |
| `JWT_EXPIRY` | no | `24h` | Token lifetime (Go duration string) |
| `LICENSE_SIGNING_KEY` | **yes** | — | Ed25519 public key (base64) for license verification |
| `FISKALY_API_KEY` | no | — | Germany fiscal API key (Phase 4) |
| `FISKALY_API_SECRET` | no | — | Germany fiscal API secret (Phase 4) |
| `ERPNEXT_URL` | no | — | ERPNext base URL (Phase 9) |
| `ERPNEXT_API_KEY` | no | — | ERPNext API key (Phase 9) |

**DATABASE_URL format:**
```
postgres://user:password@host:5432/dbname?sslmode=disable
postgres://user:password@host:5432/dbname?sslmode=require
```

---

## Database Migrations

Migrations live in `server/migrations/` as numbered SQL files.

```bash
# Run all pending migrations (via migrate command)
docker-compose exec gastrocore-server /app/gastrocore-server migrate up

# Check migration status
docker-compose exec gastrocore-server /app/gastrocore-server migrate status

# Roll back last migration
docker-compose exec gastrocore-server /app/gastrocore-server migrate down 1
```

Migration files follow the naming convention:
```
001_initial.up.sql     ← apply
001_initial.down.sql   ← rollback
002_multi_store.up.sql
002_multi_store.down.sql
...
```

**Current migrations:**

| # | Name | Tables added |
|---|---|---|
| 001 | initial | All core tables (tenants, users, products, tickets, payments…) |
| 002 | multi_store | `stores`, store FK on tenants |
| 003 | sync_events | `sync_events` outbox, `device_registrations` |
| 004 | tax_profiles | `tax_profiles`, `order_type_rules` |
| 005 | kds_online | `kitchen_tickets`, `kitchen_ticket_items`, online order metadata |

---

## GitHub Pages (Online Ordering Demo)

The `apps/online` Flutter Web app is automatically deployed to GitHub Pages.

**Workflow:** `.github/workflows/deploy-online.yml`

**Trigger:** Push to `main` branch.

**Deploy steps:**
1. `flutter build web --release --base-href /restaurant/demo/`
2. Deploy `apps/online/build/web/` to `gh-pages` branch via `peaceiris/actions-gh-pages`

**Access:** `https://<github-org>.github.io/restaurant/demo/`

**Demo mode:** The web app uses `MockApiClient` (not a real server) — all data is in-memory for demonstration.

### Manual deploy

```bash
cd apps/online
flutter pub get
flutter build web --release --base-href /restaurant/demo/

# Deploy with gh-pages CLI or push build/web/ to gh-pages branch
```

---

## Android Distribution

### Debug APK (for testing)

```bash
cd apps/pos
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK (for sideloading)

```bash
# Configure signing in android/key.properties
cd apps/pos
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Play Store (App Bundle)

```bash
cd apps/pos
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

**Signing setup** (`apps/pos/android/key.properties`):
```properties
storePassword=<your-keystore-password>
keyPassword=<your-key-password>
keyAlias=gastrocore
storeFile=../keystores/gastrocore.jks
```

See Flutter docs for creating a signing keystore.

### Flavor-specific builds

```bash
# Kiosk APK
flutter build apk --release -t lib/main_kiosk.dart --flavor kiosk

# KDS APK
flutter build apk --release -t lib/main_kds.dart --flavor kds
```

---

## CI/CD Pipelines

### `ci.yml` — Runs on every push to `main` and all pull requests

| Job | Triggers | Steps |
|---|---|---|
| `analyze` | push/PR | `flutter analyze --no-fatal-infos` |
| `test` | push/PR | `flutter test --coverage`, upload lcov artifact |
| `build-android` | after analyze+test pass | `flutter build apk --debug`, upload APK artifact |

Artifacts retained for **14 days** (APKs) and **7 days** (coverage).

### `deploy-online.yml` — Deploy web demo

Runs on push to `main`. Deploys `apps/online` Flutter Web to GitHub Pages.

### `release.yml` — Release automation

Triggered by version tags (`v*.*.*`). Creates GitHub Release with APK/AAB artifacts.

---

## Monitoring & Logs

### View container logs

```bash
# All services
docker-compose logs -f

# Server only
docker-compose logs -f gastrocore-server

# Last 100 lines
docker-compose logs --tail=100 gastrocore-server
```

### Server log format (JSON)

```json
{
  "time": "2026-03-21T13:00:00.123Z",
  "level": "INFO",
  "msg": "request completed",
  "request_id": "req-abc123",
  "method": "POST",
  "path": "/api/v1/sync/push",
  "status": 200,
  "latency_ms": 12,
  "tenant_id": "550e8400-..."
}
```

Set `LOG_LEVEL=debug` to include detailed query and sync event logs.

### Health check endpoint

```bash
# Quick status
curl -s https://api.your-restaurant.com/health | jq .

# Monitor with a cron job
*/5 * * * * curl -sf https://api.your-restaurant.com/health > /dev/null || echo "GastroCore health check failed" | mail -s "Alert" admin@example.com
```

---

## Backup & Restore

### PostgreSQL backup

```bash
# Daily backup (add to crontab)
docker-compose exec postgres pg_dump -U gastrocore gastrocore \
  | gzip > /backups/gastrocore-$(date +%Y%m%d).sql.gz

# Full crontab entry (daily at 3am)
0 3 * * * cd /opt/gastrocore && docker-compose exec -T postgres pg_dump -U gastrocore gastrocore | gzip > /backups/gastrocore-$(date +\%Y\%m\%d).sql.gz
```

### Restore

```bash
gunzip -c /backups/gastrocore-20260321.sql.gz \
  | docker-compose exec -T postgres psql -U gastrocore gastrocore
```

### Backup retention

```bash
# Keep last 30 days (add to crontab)
find /backups -name "gastrocore-*.sql.gz" -mtime +30 -delete
```

---

## Updating

### Update server image

```bash
cd /opt/gastrocore

# Pull latest code
git pull

# Rebuild server image
docker-compose build gastrocore-server

# Rolling restart (zero-downtime with multiple replicas; single container = brief restart)
docker-compose up -d gastrocore-server

# Run any new migrations
docker-compose exec gastrocore-server /app/gastrocore-server migrate up

# Verify
curl https://api.your-restaurant.com/health
```

### Rollback

```bash
# Roll back to a specific commit
git checkout <commit-sha>
docker-compose build gastrocore-server
docker-compose up -d gastrocore-server

# Roll back migration if needed
docker-compose exec gastrocore-server /app/gastrocore-server migrate down 1
```
