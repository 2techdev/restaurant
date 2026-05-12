#!/usr/bin/env python3
"""Deploy GastroCore Go server (POS backend) to Hetzner 88.99.190.108.

Build approach: there is no Go toolchain locally, but Docker is available on
the prod host. We tarball the worktree's server/ directory, ship it to the
host, run `docker run golang:1.23-alpine go build` to cross-compile a static
linux/amd64 binary, then swap it into /home/tech/gastrocore/server with
backup + systemctl restart + health check.

Worktree-aware: LOCAL_SERVER is derived from this script's own path so it
always builds the worktree it lives in (not the main repo).
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

# Build the absolute path to the worktree's server/ from this file's location
# so the script keeps targeting the right tree even when run from a different
# cwd or copied to /tmp during emergency redeploys.
LOCAL_SERVER = Path(__file__).resolve().parent / "server"

REMOTE_PROD_BINARY = "/home/tech/gastrocore/server"
REMOTE_BUILD_DIR   = "/tmp/server-build"
SYSTEMD_SERVICE    = "gastrocore.service"
HEALTH_URL         = "http://127.0.0.1:8090/health"


def connect():
    print(f"[ssh] connecting to {USERNAME}@{HOST}…")
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
        print(f"    {out[:2000]}")
    if err and rc != 0:
        print(f"  ERR: {err[:1000]}")
    return rc, out, err


def build_src_tar() -> Path:
    """Pack server/ minus build noise (.git, vendor, *.test, etc.) into a tarball."""
    ts = time.strftime("%Y%m%d-%H%M%S")
    out = Path(f"/tmp/server-src-{ts}.tar.gz")

    def excluded(info: tarfile.TarInfo) -> bool:
        bad = ("/.git/", "/.idea/", "/node_modules/", "/__pycache__/", "/.pytest_cache/")
        if any(b in info.name for b in bad):
            return True
        if info.name.endswith((".test", ".log", ".tmp")):
            return True
        return False

    with tarfile.open(out, "w:gz") as tar:
        for p in LOCAL_SERVER.rglob("*"):
            if p.is_dir():
                continue
            rel = p.relative_to(LOCAL_SERVER.parent)  # arcname = "server/..."
            info = tar.gettarinfo(p, arcname=str(rel).replace("\\", "/"))
            if info is None or excluded(info):
                continue
            with open(p, "rb") as f:
                tar.addfile(info, f)
    print(f"[pack] built {out} ({out.stat().st_size // 1024} KB)")
    return out


def main():
    ssh = connect()
    try:
        ts = time.strftime("%Y%m%d-%H%M%S")
        tar = build_src_tar()

        print(f"\n[sftp] uploading {tar.name} → /tmp/{tar.name}…")
        sftp = ssh.open_sftp()
        sftp.put(str(tar), f"/tmp/{tar.name}")
        sftp.close()

        run(ssh, f"rm -rf {REMOTE_BUILD_DIR} && mkdir -p {REMOTE_BUILD_DIR} && tar xzf /tmp/{tar.name} -C {REMOTE_BUILD_DIR}", label="extract")
        run(ssh, f"ls -la {REMOTE_BUILD_DIR}/server/ | head -10", label="verify-src")

        # Build via docker — multi-arch host, but we always target linux/amd64.
        # Using a host-mounted GOCACHE keeps re-builds fast (~5s after the first).
        # The golang image will be pulled once and reused; we don't bake it.
        build_cmd = (
            f"docker run --rm "
            f"-v {REMOTE_BUILD_DIR}/server:/src "
            f"-v /home/tech/.gocache:/root/.cache/go-build "
            f"-v /home/tech/.gomodcache:/go/pkg/mod "
            f"-w /src "
            f"-e CGO_ENABLED=0 -e GOOS=linux -e GOARCH=amd64 "
            f"golang:1.23-alpine "
            f"go build -ldflags='-s -w' -o /src/server-new ./cmd/server"
        )
        rc, _, _ = run(ssh, build_cmd, timeout=300, label="docker-build")
        if rc != 0:
            print("BUILD FAILED — aborting deploy")
            return

        run(ssh, f"ls -la {REMOTE_BUILD_DIR}/server/server-new", label="verify-binary")

        # Backup current binary
        run(ssh, f"sudo -n cp {REMOTE_PROD_BINARY} {REMOTE_PROD_BINARY}.bak.{ts}", label="backup")
        # Stop service, swap binary, restart
        run(ssh, f"sudo -n systemctl stop {SYSTEMD_SERVICE}", label="stop")
        run(ssh, f"sudo -n cp {REMOTE_BUILD_DIR}/server/server-new {REMOTE_PROD_BINARY} && sudo -n chown tech:tech {REMOTE_PROD_BINARY} && sudo -n chmod +x {REMOTE_PROD_BINARY}", label="swap")
        run(ssh, f"sudo -n systemctl start {SYSTEMD_SERVICE}", label="start")
        time.sleep(2)
        run(ssh, f"sudo -n systemctl is-active {SYSTEMD_SERVICE}", label="active?")

        # Smoke: health
        run(ssh, f"curl -s -o /dev/null -w 'health HTTP %{{http_code}} ({{time_total}}s)\\n' {HEALTH_URL}", label="health")

        print(f"\n{'='*60}")
        print(f"DEPLOY DONE — backup at {REMOTE_PROD_BINARY}.bak.{ts}")
        print(f"Rollback: sudo systemctl stop {SYSTEMD_SERVICE} && sudo cp {REMOTE_PROD_BINARY}.bak.{ts} {REMOTE_PROD_BINARY} && sudo systemctl start {SYSTEMD_SERVICE}")
        print(f"{'='*60}")
    finally:
        ssh.close()


if __name__ == "__main__":
    main()
