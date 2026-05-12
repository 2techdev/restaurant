#!/usr/bin/env python3
"""Deploy partner.gastrocore.ch Next.js app to Hetzner 88.99.190.108.

Worktree-aware (LOCAL_PARTNER derives from this script's path) so the deploy
always targets the tree that owns it — fixes the main-repo hard-code bug from
the earlier backoffice deploy script.

Idempotent setup:
  - First run: installs systemd unit, nginx vhost (no SSL config — relies on
    Cloudflare edge SSL per the user's instruction), creates remote dir.
  - Subsequent runs: tarball .next/standalone + .next/static + public + msgs,
    upload, rotate, npm install runtime deps, systemctl restart, smoke.

Build artifact expected: .next/standalone/server.js (run `npm run build` first).
"""

import io
import sys
import time
import tarfile
import paramiko
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "88.99.190.108"
PORT = 22
USERNAME = "tech"
PASSWORD = "I7wueYoeE13HBnUc6tP4"

LOCAL_PARTNER = Path(__file__).resolve().parent

REMOTE_PROD     = "/home/tech/partner"
REMOTE_BACKUPS  = "/home/tech/backups"
SYSTEMD_SERVICE = "partner.service"
SERVICE_PORT    = 3002

SYSTEMD_UNIT = f"""[Unit]
Description=GastroCore Partner Portal (Next.js)
After=network.target

[Service]
Type=simple
User=tech
WorkingDirectory={REMOTE_PROD}
Environment=NODE_ENV=production
Environment=PORT={SERVICE_PORT}
Environment=HOSTNAME=127.0.0.1
EnvironmentFile=-{REMOTE_PROD}/.env.production
ExecStart=/usr/bin/node {REMOTE_PROD}/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"""

NGINX_VHOST = f"""server {{
    listen 80;
    server_name partner.gastrocore.ch;

    # Cloudflare handles edge SSL; origin is plain HTTP. Real-IP / forwarded
    # protocol come from Cloudflare headers.
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header CF-Connecting-IP;

    client_max_body_size 50m;

    location / {{
        proxy_pass http://127.0.0.1:{SERVICE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 60s;
    }}
}}
"""


def connect():
    print(f"[ssh] {USERNAME}@{HOST}…")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USERNAME, password=PASSWORD, timeout=30)
    return ssh


def run(ssh, cmd, timeout=120, label=None):
    if label:
        print(f"  $ [{label}] {cmd[:150]}")
    else:
        print(f"  $ {cmd[:170]}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace").strip()
    err = stderr.read().decode("utf-8", errors="replace").strip()
    rc = stdout.channel.recv_exit_status()
    if out:
        print(f"    {out[:1500]}")
    if err and rc != 0:
        print(f"  ERR: {err[:800]}")
    return rc, out, err


def ensure_setup(ssh):
    """Install nginx vhost + systemd unit if missing. Idempotent."""
    rc, out, _ = run(ssh, f"test -f /etc/nginx/sites-enabled/partner.gastrocore.ch && echo ok || echo missing", label="nginx-check")
    if "missing" in out:
        print("[setup] installing nginx vhost…")
        # Write vhost via sudo tee
        nginx_b64 = __import__("base64").b64encode(NGINX_VHOST.encode()).decode()
        run(ssh,
            f"echo {nginx_b64} | base64 -d | sudo -n tee /etc/nginx/sites-available/partner.gastrocore.ch >/dev/null",
            label="nginx-write")
        run(ssh, "sudo -n ln -sf /etc/nginx/sites-available/partner.gastrocore.ch /etc/nginx/sites-enabled/partner.gastrocore.ch", label="nginx-symlink")
        run(ssh, "sudo -n nginx -t && sudo -n systemctl reload nginx", label="nginx-reload")
    else:
        print("[setup] nginx vhost present, skipping")

    rc, out, _ = run(ssh, f"test -f /etc/systemd/system/{SYSTEMD_SERVICE} && echo ok || echo missing", label="systemd-check")
    if "missing" in out:
        print("[setup] installing systemd unit…")
        unit_b64 = __import__("base64").b64encode(SYSTEMD_UNIT.encode()).decode()
        run(ssh,
            f"echo {unit_b64} | base64 -d | sudo -n tee /etc/systemd/system/{SYSTEMD_SERVICE} >/dev/null",
            label="unit-write")
        run(ssh, f"sudo -n systemctl daemon-reload && sudo -n systemctl enable {SYSTEMD_SERVICE}", label="enable")
    else:
        print("[setup] systemd unit present, skipping")

    run(ssh, f"mkdir -p {REMOTE_PROD} {REMOTE_BACKUPS}", label="dirs")


def build_tar(ts: str) -> Path:
    """Pack the Next.js standalone build into a single tarball."""
    out = Path(f"/tmp/partner-deploy-{ts}.tar.gz")
    next_dir = LOCAL_PARTNER / ".next"
    standalone = next_dir / "standalone"
    static = next_dir / "static"
    public = LOCAL_PARTNER / "public"
    messages = LOCAL_PARTNER / "messages"

    if not (standalone / "server.js").exists():
        raise RuntimeError(f"missing {standalone}/server.js — run `npm run build` first")

    with tarfile.open(out, "w:gz") as tar:
        # Standalone server bundle at root
        for p in standalone.rglob("*"):
            if p.is_file():
                rel = p.relative_to(standalone)
                tar.add(p, arcname=str(rel).replace("\\", "/"))
        # Static chunks (Next standalone doesn't copy these by default)
        if static.exists():
            for p in static.rglob("*"):
                if p.is_file():
                    rel = Path(".next/static") / p.relative_to(static)
                    tar.add(p, arcname=str(rel).replace("\\", "/"))
        # Public assets
        if public.exists():
            for p in public.rglob("*"):
                if p.is_file():
                    rel = Path("public") / p.relative_to(public)
                    tar.add(p, arcname=str(rel).replace("\\", "/"))
        # Messages (standalone doesn't always pick them up)
        if messages.exists():
            for p in messages.rglob("*"):
                if p.is_file():
                    rel = Path("messages") / p.relative_to(messages)
                    tar.add(p, arcname=str(rel).replace("\\", "/"))

    print(f"[pack] built {out} ({out.stat().st_size // 1024} KB)")
    return out


def main():
    ts = time.strftime("%Y%m%d-%H%M%S")
    tar = build_tar(ts)

    ssh = connect()
    try:
        ensure_setup(ssh)

        print(f"\n[backup] snapshotting current {REMOTE_PROD} → {REMOTE_BACKUPS}/partner-{ts}…")
        run(ssh, f"mkdir -p {REMOTE_BACKUPS}/partner-{ts} && (cp -a {REMOTE_PROD}/. {REMOTE_BACKUPS}/partner-{ts}/ 2>/dev/null || true)", label="backup")

        print(f"\n[sftp] uploading {tar.name}…")
        sftp = ssh.open_sftp()
        sftp.put(str(tar), f"/tmp/{tar.name}")
        sftp.close()

        print(f"\n[rotate] {REMOTE_PROD} → {REMOTE_PROD}_old_{ts}")
        run(ssh, f"if [ -d {REMOTE_PROD} ] && [ -f {REMOTE_PROD}/server.js ]; then mv {REMOTE_PROD} {REMOTE_PROD}_old_{ts}; fi && mkdir -p {REMOTE_PROD}", label="rotate")

        print(f"\n[extract] tar → {REMOTE_PROD}")
        run(ssh, f"cd {REMOTE_PROD} && tar xzf /tmp/{tar.name} && ls -la | head -10", label="extract")

        # Restore .env.production if present in rotated dir
        run(ssh, f"if [ -f {REMOTE_PROD}_old_{ts}/.env.production ]; then cp {REMOTE_PROD}_old_{ts}/.env.production {REMOTE_PROD}/.env.production; fi", label="env-restore")
        # Write the api URL env if missing (points partner at the local Go server)
        run(ssh, f"if [ ! -f {REMOTE_PROD}/.env.production ]; then echo 'API_BASE_URL=http://127.0.0.1:8090/api/v1' | tee {REMOTE_PROD}/.env.production >/dev/null; fi", label="env-default")

        # Restart service
        run(ssh, f"sudo -n systemctl restart {SYSTEMD_SERVICE}", label="restart")
        time.sleep(2)
        run(ssh, f"sudo -n systemctl is-active {SYSTEMD_SERVICE}", label="active?")

        # Smoke
        run(ssh, f"curl -s -o /dev/null -w 'origin / HTTP %{{http_code}}\\n' http://127.0.0.1:{SERVICE_PORT}/", label="smoke-origin")
        run(ssh, f"curl -s -o /dev/null -w 'origin /tr/login HTTP %{{http_code}}\\n' http://127.0.0.1:{SERVICE_PORT}/tr/login", label="smoke-login")
        run(ssh, f"sudo -n journalctl -u {SYSTEMD_SERVICE} -n 20 --no-pager 2>&1 | tail -20", label="journal")

        print(f"\n{'='*60}\nDEPLOY DONE — backup at {REMOTE_BACKUPS}/partner-{ts}\n{'='*60}")
    finally:
        ssh.close()


if __name__ == "__main__":
    main()
