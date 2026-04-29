# Hetzner Deploy Runbook — backoffice (Next.js 15)

Bu runbook backoffice'in Hetzner sunucusunda nasıl deploy edileceğini anlatır. Mevcut
`gastro2hub` (Go API) ve diğer servisler bu sunucuda zaten çalışıyor varsayımıyla yazıldı.

## Önkoşullar

- Hetzner Cloud sunucusu (Ubuntu 22.04 LTS, en az 2 vCPU / 2GB RAM)
- DNS: `backoffice.gastrocore.ch` A kaydı sunucu IP'sine işaretli
- SSH erişimi (root veya sudo'lu kullanıcı)
- Docker + docker compose kurulu (yoksa aşağıda)
- (Opsiyonel) nginx veya Caddy kurulu (reverse proxy + SSL için)

## 1. Sunucu hazırlığı (sadece ilk kurulumda)

```bash
ssh root@<HETZNER_IP>

# Docker
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# nginx (opsiyon A)
apt update && apt install -y nginx certbot python3-certbot-nginx

# Caddy (opsiyon B — daha basit, otomatik SSL)
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

## 2. Repo'yu çek

```bash
mkdir -p /opt/gastrocore
cd /opt/gastrocore
git clone git@github.com:<your-org>/Restaurant.git
# ya da pull:
cd /opt/gastrocore/Restaurant && git pull
```

## 3. Env dosyaları

```bash
cd /opt/gastrocore/Restaurant/apps/backoffice
cp .env.example .env.production
nano .env.production
# - API_BASE_URL=https://api.2hub.ch/api/v1
# - NEXT_PUBLIC_API_URL=https://api.2hub.ch/api/v1
# - NEXT_PUBLIC_WS_URL=wss://ws.2hub.ch
# - AUTH_COOKIE_SECRET=<rastgele 32+ karakter>
# - NODE_ENV=production
```

Rastgele secret üretmek:

```bash
openssl rand -hex 32
```

## 4. Docker image build + run

### 4a. Standalone (en basit)

```bash
cd /opt/gastrocore/Restaurant/apps/backoffice
docker build -t gastrocore-backoffice:latest .
docker run -d \
  --name backoffice \
  --restart unless-stopped \
  -p 127.0.0.1:3001:3001 \
  --env-file .env.production \
  gastrocore-backoffice:latest
```

`-p 127.0.0.1:3001:3001` — yalnızca localhost'a bind ediliyor; reverse proxy
public'e açacak.

### 4b. docker-compose ile (`Restaurant/` root'unda mevcut compose dosyasına ekleyin)

`docker-compose.yml`'a eklenecek servis (`deploy/docker-compose.backoffice.yml` örneği aşağıda):

```yaml
services:
  backoffice:
    build:
      context: ./apps/backoffice
    image: gastrocore-backoffice:latest
    container_name: backoffice
    restart: unless-stopped
    ports:
      - "127.0.0.1:3001:3001"
    env_file:
      - ./apps/backoffice/.env.production
    networks:
      - default
```

```bash
docker compose up -d --build backoffice
docker compose logs -f backoffice
```

## 5. Reverse proxy + SSL

### 5a. nginx + certbot

```bash
# Config'i kopyala
cp /opt/gastrocore/Restaurant/deploy/nginx/backoffice.conf \
   /etc/nginx/sites-available/backoffice.gastrocore.ch

ln -sf /etc/nginx/sites-available/backoffice.gastrocore.ch \
       /etc/nginx/sites-enabled/

nginx -t && systemctl reload nginx

# Let's Encrypt sertifika al
certbot --nginx -d backoffice.gastrocore.ch \
        --non-interactive --agree-tos -m admin@gastrocore.ch

# Cron auto-renew zaten certbot install ile geliyor: systemctl status certbot.timer
```

### 5b. Caddy (otomatik SSL — önerilen)

```bash
cp /opt/gastrocore/Restaurant/deploy/Caddyfile.backoffice /etc/caddy/Caddyfile
systemctl reload caddy
# Caddy ilk istekte Let's Encrypt'ten sertifika çekecek (DNS doğru olmalı).
```

## 6. Doğrulama

```bash
# Container ayakta mı?
docker ps | grep backoffice

# Local 3001 cevap veriyor mu?
curl -i http://127.0.0.1:3001

# Public HTTPS
curl -I https://backoffice.gastrocore.ch
```

Tarayıcıdan `https://backoffice.gastrocore.ch` aç, login ekranını gör.

## 7. Update (yeni sürüm)

```bash
cd /opt/gastrocore/Restaurant
git pull

# Backoffice'i yeniden build et + restart
cd apps/backoffice
docker build -t gastrocore-backoffice:latest .
docker stop backoffice && docker rm backoffice
docker run -d \
  --name backoffice \
  --restart unless-stopped \
  -p 127.0.0.1:3001:3001 \
  --env-file .env.production \
  gastrocore-backoffice:latest
```

ya da compose ile:

```bash
docker compose up -d --build backoffice
```

## 8. Loglar

```bash
docker logs -f backoffice
journalctl -u nginx -f         # nginx erişim/hata
journalctl -u caddy -f         # caddy
tail -f /var/log/nginx/access.log
```

## 9. Geri alma

Önceki image tag'iyle restart:

```bash
docker tag gastrocore-backoffice:latest gastrocore-backoffice:rollback
# git checkout <eski-commit>; docker build -t gastrocore-backoffice:latest .
# docker stop backoffice; docker rm backoffice; docker run ... yukarıdaki gibi
```

## 10. Pilot kontrol listesi

- [ ] DNS `backoffice.gastrocore.ch` IP'ye işaretli
- [ ] `.env.production` dolduruldu (özellikle `AUTH_COOKIE_SECRET`)
- [ ] Docker container ayakta (`docker ps`)
- [ ] HTTPS sertifikası geçerli
- [ ] Login akışı çalışıyor (`POST /api/auth/login` → cookie set)
- [ ] Menü CRUD + "POS'a Yayınla" butonu cevap veriyor
- [ ] Dashboard KPI ve 7 günlük chart yükleniyor

## Sorun giderme

| Sorun | Çözüm |
|-------|-------|
| 502 Bad Gateway | Container kapalı: `docker logs backoffice` ile bak. |
| Login sonrası 401 | `API_BASE_URL` yanlış ya da backend cookie'yi kabul etmiyor. |
| CORS hatası | `next.config.ts`'te rewrite yok; backend doğrudan tarayıcıdan değil, `/api/proxy/*` üzerinden çağrılır. |
| i18n 404 | `messages/<locale>.json` dosyası container'da eksik — Dockerfile `COPY messages` satırını kontrol edin. |
| HMR yok | Production build standalone — sadece `pnpm dev` modunda HMR var. |
