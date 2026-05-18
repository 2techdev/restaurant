#!/usr/bin/env python3
"""Deploy Go server BINARY (gastrocore.service) to Hetzner 88.

Correct topology (verified 2026-05-11):
  - systemd unit: gastrocore.service
  - ExecStart: /home/tech/gastrocore/server
  - User: tech
  - EnvironmentFile: /home/tech/gastrocore/.env
  - NOT a Docker container.

Flow:
  1. Tar local server/ source (excl bin, .git, *.exe)
  2. SFTP → /tmp/
  3. On host: extract → docker-build cross-compile (golang:1.23-alpine)
  4. Backup current /home/tech/gastrocore/server → server.bak.<ts>
  5. Swap binary, chmod +x, sudo systemctl restart gastrocore.service
  6. Smoke (origin localhost:8090 + popular route)
"""

import os
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

# Worktree-aware: server/ sits next to this script. Running from a worktree
# bundles THAT worktree's source, not the main repo. Override with
# GASTROCORE_DEPLOY_SERVER_DIR env var if you ever need a manual override.
LOCAL_SERVER = Path(os.environ.get("GASTROCORE_DEPLOY_SERVER_DIR", str(Path(__file__).resolve().parent / "server")))
REMOTE_DIR = "/home/tech/gastrocore"
SERVICE = "gastrocore.service"


def connect():
    print(f"[ssh] connecting to {USERNAME}@{HOST}…")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USERNAME, password=PASSWORD, timeout=30)
    return ssh


def run(ssh, cmd, timeout=120, label=None, show_full=False):
    if label:
        print(f"  $ [{label}] {cmd[:140]}")
    else:
        print(f"  $ {cmd[:160]}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="replace").strip()
    err = stderr.read().decode("utf-8", errors="replace").strip()
    rc = stdout.channel.recv_exit_status()
    if out:
        max_len = 6000 if show_full else 1800
        print(f"    {out[:max_len]}")
    if err and rc != 0:
        print(f"  ERR: {err[:1500]}")
    return rc, out, err


def sudo_run(ssh, cmd, timeout=120, label=None):
    full = f"echo '{PASSWORD}' | sudo -S -p '' {cmd}"
    return run(ssh, full, timeout=timeout, label=label or "sudo")


def build_tar(ts: str) -> Path:
    tar_path = LOCAL_SERVER.parent / f"gastrocore-src-{ts}.tar.gz"
    print(f"[tar] building {tar_path.name}…")

    EXCLUDED_DIRS = {"bin", ".git", "node_modules", ".claude", "test-results"}
    EXCLUDED_SUFFIXES = (".exe", ".tar.gz", ".log")
    n_files = 0
    with tarfile.open(str(tar_path), "w:gz", compresslevel=6) as tar:
        for root, dirs, files in os.walk(LOCAL_SERVER):
            dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
            for f in files:
                if f.endswith(EXCLUDED_SUFFIXES):
                    continue
                p = Path(root) / f
                try:
                    rel = p.relative_to(LOCAL_SERVER)
                except ValueError:
                    continue
                arcname = "server/" + str(rel).replace("\\", "/")
                try:
                    tar.add(str(p), arcname=arcname, recursive=False)
                    n_files += 1
                except Exception as e:
                    print(f"  WARN: {arcname}: {e}")

    size_mb = tar_path.stat().st_size / (1024 * 1024)
    print(f"  → {n_files} files, {size_mb:.1f} MB")
    return tar_path


def main():
    print("=" * 60)
    print(f"DEPLOY gastrocore binary TO 88 ({HOST})")
    print("=" * 60)

    ts = time.strftime("%Y%m%d-%H%M%S")
    print(f"[ts] {ts}")

    tar_path = build_tar(ts)
    remote_tar = f"/tmp/{tar_path.name}"

    ssh = connect()

    # 1. Pre-probe
    print("\n[probe] current state")
    run(ssh, f"sudo -n systemctl is-active {SERVICE} || true", label="svc")
    run(ssh, f"ls -lh {REMOTE_DIR}/server", label="binary")
    run(ssh, "curl -s -o /dev/null -w 'health %{http_code}\\n' http://127.0.0.1:8090/health", label="health-pre")

    # 2. Upload
    print(f"\n[sftp] uploading {tar_path.name}")
    sftp = ssh.open_sftp()
    sftp.put(str(tar_path), remote_tar)
    sftp.close()
    run(ssh, f"ls -lh {remote_tar} && gzip -t {remote_tar} && echo OK", label="verify-upload")

    # 3. Extract
    build_dir = f"/tmp/build-gastrocore-{ts}"
    run(
        ssh,
        f"mkdir -p {build_dir} && cd {build_dir} && tar xzf {remote_tar} && "
        f"ls server/cmd/server/main.go && ls server/internal/menu/popular.go",
        label="extract",
        timeout=120,
    )

    # 4. Docker cross-compile (no need for full image, just the binary)
    print("\n[docker-build] cross-compile via golang:1.23-alpine (2-4 min)")
    run(
        ssh,
        f"cd {build_dir}/server && docker run --rm -v $(pwd):/src -w /src "
        f"--network host golang:1.23-alpine sh -c '"
        f"apk add --no-cache git ca-certificates >/dev/null && "
        f"CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags=\"-s -w\" "
        f"-o /src/server-new ./cmd/server' && "
        f"ls -lh {build_dir}/server/server-new && file {build_dir}/server/server-new && "
        f"sha256sum {build_dir}/server/server-new",
        timeout=600,
        label="go-build",
        show_full=True,
    )

    # 5. Backup current
    print("\n[backup] current binary")
    run(
        ssh,
        f"cp {REMOTE_DIR}/server {REMOTE_DIR}/server.bak.{ts} && "
        f"ls -lh {REMOTE_DIR}/server.bak.{ts}",
        label="backup",
    )

    # 6. Swap (binary write needs to go to /home/tech/gastrocore as tech user)
    print("\n[swap] move new binary into place")
    run(
        ssh,
        f"cp {build_dir}/server/server-new {REMOTE_DIR}/server.new.{ts} && "
        f"chmod +x {REMOTE_DIR}/server.new.{ts} && "
        f"mv {REMOTE_DIR}/server.new.{ts} {REMOTE_DIR}/server && "
        f"ls -lh {REMOTE_DIR}/server",
        label="swap",
    )

    # 7. Restart service
    print(f"\n[systemd] restart {SERVICE}")
    sudo_run(ssh, f"systemctl restart {SERVICE}", label="restart", timeout=30)
    time.sleep(3)
    sudo_run(ssh, f"systemctl is-active {SERVICE}", label="is-active")
    sudo_run(ssh, f"systemctl status {SERVICE} --no-pager | head -12", label="status")

    # 8. Smoke
    print("\n[smoke] post-deploy")
    run(ssh, "curl -s -o /dev/null -w 'health HTTP %{http_code} (%{time_total}s)\\n' http://127.0.0.1:8090/health", label="health")
    run(ssh, "curl -s http://127.0.0.1:8090/health", label="health-body")
    # Popular route — bogus UUID should hit auth/tenant check, not 404 "page not found"
    run(
        ssh,
        "curl -s -o /dev/null -w 'POPULAR route HTTP %{http_code}\\n' -X PATCH "
        "-H 'Content-Type: application/json' -d '{\"is_popular_online\":true}' "
        "http://127.0.0.1:8090/api/v1/menu/products/00000000-0000-0000-0000-000000000000/popular",
        label="popular",
    )
    # Should be 401 UNAUTHORIZED (route exists, hits middleware) — NOT 404
    run(
        ssh,
        "curl -s -X PATCH -H 'Content-Type: application/json' -d '{\"is_popular_online\":true}' "
        "http://127.0.0.1:8090/api/v1/menu/products/00000000-0000-0000-0000-000000000000/popular",
        label="popular-body",
    )
    sudo_run(ssh, f"journalctl -u {SERVICE} -n 25 --no-pager | tail -20", label="journal")

    ssh.close()

    print("\n" + "=" * 60)
    print(f"DEPLOY DONE — backup at {REMOTE_DIR}/server.bak.{ts}")
    print(f"Rollback: ssh tech@{HOST} 'sudo systemctl stop {SERVICE} && "
          f"cp {REMOTE_DIR}/server.bak.{ts} {REMOTE_DIR}/server && "
          f"sudo systemctl start {SERVICE}'")
    print("=" * 60)


if __name__ == "__main__":
    main()
