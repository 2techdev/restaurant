#!/usr/bin/env python3
"""Deploy backoffice (Next.js standalone) to Hetzner — Servis 2.

Pattern: pilot/DEPLOY_RUNBOOK.md §Servis 2 (manuel adımları script'leştirir).

What it does:
  0. KURAL 0 backup: code-snapshot + pm2 jlist on Hetzner
  1. Verify local build artifact present (.next/standalone/server.js)
  2. Build local tar (.next/standalone + .next/static + public if exists)
  3. SFTP tar → /tmp/backoffice-deploy-<TS>.tar.gz
  4. Rotate: gastro_backoffice → gastro_backoffice_old_<TS>
  5. Extract new tar; copy .env + ecosystem.config.js from rotation dir
  6. npm install --omit=dev (Next.js standalone needs runtime deps)
  7. pm2 reload gastro-backoffice
  8. Smoke (origin localhost:3002, public via curl)

Rollback: ssh tech@... 'mv gastro_backoffice gastro_backoffice_failed && mv gastro_backoffice_old_<TS> gastro_backoffice && pm2 reload gastro-backoffice'
"""

import io
import os
import sys
import time
import tarfile
import stat
import paramiko
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "88.99.190.108"
PORT = 22
USERNAME = "tech"
PASSWORD = "I7wueYoeE13HBnUc6tP4"

# Worktree-aware: deploy from wherever this script lives (so running it from
# .claude/worktrees/<branch>/apps/backoffice/ ships THAT worktree's build,
# not the main repo). Override with BACKOFFICE_DEPLOY_DIR env var if needed.
LOCAL_BACKOFFICE = Path(os.environ.get("BACKOFFICE_DEPLOY_DIR", str(Path(__file__).resolve().parent)))
# 88's backoffice lives under /home/tech/backoffice (NOT /gastro_backoffice —
# that path was a leftover from when this script targeted the wrong server).
# Service is systemd `backoffice.service` running `node server.js` on
# 127.0.0.1:3001 as user `tech`. PM2 is NOT installed. Verified 2026-05-11
# after a no-op deploy that wrote to the legacy path. See DEPLOY_RUNBOOK
# §Servis 2 for the canonical topology.
REMOTE_PROD = "/home/tech/backoffice"
REMOTE_BACKUPS = "/home/tech/backups"
SYSTEMD_SERVICE = "backoffice.service"
SERVICE_PORT = 3001
# Legacy PM2 app name retained for older smoke / log queries; new deploys use systemd.
PM2_APP = "gastro-backoffice"


def connect():
    print(f"[ssh] connecting to {USERNAME}@{HOST}…")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USERNAME, password=PASSWORD, timeout=30)
    return ssh


def run(ssh, cmd, timeout=120, label=None):
    if label:
        print(f"  $ [{label}] {cmd[:120]}")
    else:
        print(f"  $ {cmd[:160]}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace").strip()
    err = stderr.read().decode("utf-8", errors="replace").strip()
    rc = stdout.channel.recv_exit_status()
    if out:
        print(f"    {out[:1200]}")
    if err and rc != 0:
        print(f"  ERR: {err[:600]}")
    return rc, out, err


def build_tar(ts: str) -> Path:
    """Bundle .next/standalone + .next/static + public into a single tar.

    Layout (matches DEPLOY_RUNBOOK §Servis 2 step 1):
      <root>/server.js
      <root>/.next/static/...
      <root>/public/...        (if exists)
      <root>/messages/...      (if exists; runtime needs it for next-intl SSR)
      <root>/node_modules/...  (only @prisma if exists; backoffice doesn't use prisma)
    """
    standalone = LOCAL_BACKOFFICE / ".next" / "standalone"
    static_dir = LOCAL_BACKOFFICE / ".next" / "static"
    public_dir = LOCAL_BACKOFFICE / "public"
    messages_dir = LOCAL_BACKOFFICE / "messages"

    if not (standalone / "server.js").exists():
        raise FileNotFoundError(f"{standalone}/server.js missing — run npm run build")
    if not static_dir.exists():
        raise FileNotFoundError(f"{static_dir} missing")

    tar_path = LOCAL_BACKOFFICE / f"backoffice-deploy-{ts}.tar.gz"
    print(f"[tar] building {tar_path.name}…")

    def add_tree(tar: tarfile.TarFile, src: Path, arcname_prefix: str):
        for root, dirs, files in os.walk(src):
            for f in files:
                p = Path(root) / f
                try:
                    rel = p.relative_to(src)
                except ValueError:
                    continue
                arcname = (
                    arcname_prefix + ("/" + str(rel).replace("\\", "/") if str(rel) else "")
                ).lstrip("/")
                try:
                    tar.add(str(p), arcname=arcname, recursive=False)
                except Exception as e:
                    print(f"  WARN: {arcname}: {e}")

    n_files = 0
    with tarfile.open(str(tar_path), "w:gz", compresslevel=6) as tar:
        # standalone bundle root → tar root (so server.js lands at root)
        add_tree(tar, standalone, "")
        # static under .next/static
        add_tree(tar, static_dir, ".next/static")
        # public if present
        if public_dir.exists():
            add_tree(tar, public_dir, "public")
        # messages (next-intl SSR needs runtime access)
        if messages_dir.exists():
            add_tree(tar, messages_dir, "messages")
        n_files = len(tar.getnames())

    size_mb = tar_path.stat().st_size / (1024 * 1024)
    print(f"  → {n_files} files, {size_mb:.1f} MB")
    return tar_path


def main():
    print("=" * 60)
    print("DEPLOY BACKOFFICE TO HETZNER (gastro-backoffice, port 3002)")
    print("=" * 60)

    ts = time.strftime("%Y%m%d-%H%M%S")
    print(f"[ts] {ts}")

    # 1. Verify build
    if not (LOCAL_BACKOFFICE / ".next" / "standalone" / "server.js").exists():
        print("FATAL: .next/standalone/server.js not found. Run npm run build.")
        sys.exit(1)
    print("[verify] .next/standalone/server.js OK")

    # 2. Build tar locally
    tar_path = build_tar(ts)
    remote_tar = f"/tmp/{tar_path.name}"

    # 3. SSH connect
    ssh = connect()

    # 4. Pre-deploy state probe
    print("\n[probe] current backoffice state on Hetzner…")
    run(ssh, f"ls -d {REMOTE_PROD} 2>/dev/null || echo 'NOT_FOUND'", label="path")
    run(ssh, f"sudo -n systemctl is-active {SYSTEMD_SERVICE} 2>&1 || echo 'SERVICE_NOT_RUNNING'", label="svc")
    run(ssh, f"ss -tlnp 2>/dev/null | grep :{SERVICE_PORT} || echo 'PORT_NOT_LISTENING'", label="port")
    run(ssh, "sudo -n whoami", label="sudo")

    # 5. KURAL 0 backup
    print(f"\n[backup] KURAL 0 — {REMOTE_BACKUPS}/backoffice-{ts}/")
    backup_dir = f"{REMOTE_BACKUPS}/backoffice-{ts}"
    run(ssh, f"mkdir -p {backup_dir}")
    run(
        ssh,
        f"if [ -d {REMOTE_PROD} ]; then "
        f"cp -a {REMOTE_PROD} {backup_dir}/code-snapshot && "
        f"echo 'code-snapshot OK'; "
        f"else echo 'No existing code to snapshot (fresh deploy)'; fi",
        timeout=180,
        label="snapshot",
    )
    run(ssh, f"pm2 jlist > {backup_dir}/pm2.json && wc -c {backup_dir}/pm2.json", label="pm2-jlist")
    # Next.js standalone reads .env.production (not .env). The pre-2026-05-11
    # version checked only .env which never matched, so backups were lost.
    run(
        ssh,
        f"for f in .env .env.production .env.local; do "
        f"  [ -f {REMOTE_PROD}/$f ] && cp {REMOTE_PROD}/$f {backup_dir}/$f.bak; "
        f"done; ls -la {backup_dir}/",
        label="env-bak",
    )
    run(ssh, f"ls -la {backup_dir}/", label="verify-backup")

    # 6. Upload tar
    print(f"\n[sftp] uploading {tar_path.name} → {remote_tar}…")
    sftp = ssh.open_sftp()
    sftp.put(str(tar_path), remote_tar)
    sftp.close()
    run(ssh, f"ls -lh {remote_tar} && gzip -t {remote_tar} && echo 'GZIP_OK'", label="verify-upload")

    # 7. Rotate + extract
    print(f"\n[rotate] {REMOTE_PROD} → {REMOTE_PROD}_old_{ts}")
    rotation_dir = f"{REMOTE_PROD}_old_{ts}"
    run(
        ssh,
        f"if [ -d {REMOTE_PROD} ]; then mv {REMOTE_PROD} {rotation_dir}; fi && "
        f"mkdir -p {REMOTE_PROD}",
        label="rotate",
    )

    print(f"\n[extract] tar → {REMOTE_PROD}")
    run(
        ssh,
        f"cd {REMOTE_PROD} && tar xzf {remote_tar} && ls -la | head -10",
        timeout=180,
        label="extract",
    )

    # 8. Restore .env files + ecosystem.config.js from rotation dir.
    # Next.js standalone consumes .env.production at runtime — the previous
    # version only checked `.env` (without the .production suffix) and so
    # silently left the new install env-less, causing `backoffice.service`
    # to fail with "Failed to load environment files". Verified 2026-05-11
    # (second occurrence in one week). We now copy every flavour that exists.
    print("\n[env] restoring .env / .env.production / .env.local from rotation snapshot")
    run(
        ssh,
        f"for f in .env .env.production .env.local; do "
        f"  if [ -f {rotation_dir}/$f ]; then "
        f"    cp {rotation_dir}/$f {REMOTE_PROD}/$f && echo \"$f restored\"; "
        f"  fi; "
        f"done; "
        f"if ! ls {REMOTE_PROD}/.env* >/dev/null 2>&1; then "
        f"  echo 'WARN: no env files in rotation; first deploy?'; "
        f"fi",
        label="env-restore",
    )
    run(
        ssh,
        f"if [ -f {rotation_dir}/ecosystem.config.js ]; then "
        f"cp {rotation_dir}/ecosystem.config.js {REMOTE_PROD}/ecosystem.config.js && "
        f"echo 'ecosystem.config.js restored'; "
        f"else echo 'WARN: no ecosystem.config.js in rotation'; fi",
        label="ecosystem-restore",
    )

    # 9. npm install --omit=dev (standalone bundle ships incomplete node_modules)
    print("\n[npm] npm install --omit=dev (runtime deps fill-in)…")
    run(
        ssh,
        f"cd {REMOTE_PROD} && npm install --omit=dev --prefer-offline --no-audit --no-fund 2>&1 | tail -5",
        timeout=300,
        label="npm-install",
    )

    # 10. systemd restart — 88 uses systemd `backoffice.service`, NOT PM2.
    # The previous PM2 reload path was a hold-over from when this script
    # targeted the wrong server; left a 2026-05-11 deploy in no-op state
    # because pm2 wasn't installed.
    #
    # The env file must be owned by `tech` (systemd unit runs as User=tech);
    # `sudo cp` from the rotation snapshot leaves it root-owned and the
    # service hits EACCES at startup. Restore ownership before restart.
    print(f"\n[env-perms] chown {REMOTE_PROD}/.env.production tech:tech")
    run(
        ssh,
        f"sudo -n chown tech:tech {REMOTE_PROD}/.env.production 2>/dev/null && "
        f"sudo -n chmod 600 {REMOTE_PROD}/.env.production 2>/dev/null && "
        f"ls -la {REMOTE_PROD}/.env.production",
        label="env-chown",
    )

    print(f"\n[systemd] restart {SYSTEMD_SERVICE}")
    run(ssh, f"sudo -n systemctl restart {SYSTEMD_SERVICE}", label="systemctl-restart", timeout=60)
    time.sleep(3)
    run(ssh, f"sudo -n systemctl is-active {SYSTEMD_SERVICE}", label="systemctl-is-active")
    run(ssh, f"sudo -n systemctl status {SYSTEMD_SERVICE} --no-pager 2>&1 | head -10", label="systemctl-status")

    # 11. Smoke
    print("\n[smoke] post-deploy verification")
    run(
        ssh,
        f"curl -s -o /dev/null -w 'origin / HTTP %{{http_code}} (%{{time_total}}s)\\n' http://127.0.0.1:{SERVICE_PORT}/",
        label="origin-/",
    )
    run(
        ssh,
        f"curl -s -o /dev/null -w 'origin /tr/login HTTP %{{http_code}}\\n' http://127.0.0.1:{SERVICE_PORT}/tr/login",
        label="origin-login",
    )
    run(
        ssh,
        f"curl -s -o /dev/null -w 'origin /tr/menu/modifiers HTTP %{{http_code}}\\n' http://127.0.0.1:{SERVICE_PORT}/tr/menu/modifiers",
        label="origin-modifiers",
    )
    run(
        ssh,
        f"sudo -n journalctl -u {SYSTEMD_SERVICE} -n 30 --no-pager 2>&1 | tail -20",
        label="journal",
    )

    ssh.close()

    print("\n" + "=" * 60)
    print(f"DEPLOY DONE — backup at {backup_dir}")
    print(
        f"Rollback: ssh tech@{HOST} 'sudo systemctl stop {SYSTEMD_SERVICE} && "
        f"sudo mv {REMOTE_PROD} {REMOTE_PROD}_failed_{ts} && "
        f"sudo mv {rotation_dir} {REMOTE_PROD} && "
        f"sudo chown tech:tech {REMOTE_PROD}/.env.production && "
        f"sudo systemctl start {SYSTEMD_SERVICE}'"
    )
    print("=" * 60)


if __name__ == "__main__":
    main()
