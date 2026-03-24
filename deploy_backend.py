#!/usr/bin/env python3
"""Deploy GastroCore Go backend to VPS via SSH (paramiko)."""

import os
import sys
import tarfile
import io
import time
import re
import paramiko

HOST = "192.168.1.134"
USER = "tech"
PASSWORD = "051160"
DEPLOY_DIR = "/home/tech/gastrocore/server"
LOCAL_SERVER_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server")


def run(ssh, cmd, show=True):
    """Run command without PTY so stdin pipes work."""
    if show:
        print(f"\n$ {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    rc = stdout.channel.recv_exit_status()
    if out and show:
        print(out, end="")
    if err and show:
        # Filter noise
        lines = [l for l in err.splitlines()
                 if not any(x in l.lower() for x in ["[sudo]", "password for tech", "sorry, try again"])]
        if lines:
            print("[stderr] " + "\n".join(lines))
    return rc, out, err


def sudo_run(ssh, cmd, show=True):
    """Run with sudo using stdin password injection."""
    if show:
        print(f"\n$ sudo {cmd}")
    transport = ssh.get_transport()
    chan = transport.open_session()
    chan.get_pty()  # Need PTY for sudo
    chan.exec_command(f"sudo -S -p 'SUDOPROMPT' {cmd}")
    # Feed password when prompted
    buf = b""
    out_parts = []
    chan.settimeout(30)
    import select as sel
    while True:
        if chan.exit_status_ready() and not chan.recv_ready():
            break
        r, _, _ = sel.select([chan], [], [], 1.0)
        if r:
            data = chan.recv(4096)
            if not data:
                break
            buf += data
            if b"SUDOPROMPT" in buf or b"password" in buf.lower():
                chan.sendall((PASSWORD + "\n").encode())
                buf = b""
            else:
                out_parts.append(data.decode(errors="replace"))
    # Drain remaining
    while chan.recv_ready():
        out_parts.append(chan.recv(4096).decode(errors="replace"))
    rc = chan.recv_exit_status()
    out = "".join(out_parts)
    if out and show:
        print(out, end="")
    return rc, out


def make_tarball(local_dir):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(local_dir, arcname="server")
    buf.seek(0)
    return buf


def main():
    print(f"=== GastroCore Backend Deploy -> {HOST} ===\n")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, password=PASSWORD, timeout=15)
    print("Connected.\n")

    # 1. Current state
    print("--- Current Docker state ---")
    run(ssh, "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")

    # 2. Check if docker-compose works without sudo
    print("\n--- Checking docker-compose access ---")
    rc, out, _ = run(ssh, "which docker-compose || which docker")
    print(f"Docker tools available: {out.strip()}")

    # Test if docker-compose can run without sudo
    rc2, out2, _ = run(ssh, "docker-compose version 2>/dev/null || docker compose version 2>/dev/null")
    dc_cmd = "docker-compose" if rc2 == 0 and "docker-compose" in out2 else "docker compose"
    print(f"Using: {dc_cmd}")

    # 3. Upload server/ as tarball
    print(f"\n--- Uploading server/ -> {DEPLOY_DIR} ---")
    run(ssh, f"mkdir -p {DEPLOY_DIR}")
    tarball = make_tarball(LOCAL_SERVER_DIR)
    size_kb = tarball.getbuffer().nbytes // 1024
    sftp = ssh.open_sftp()
    remote_tar = "/home/tech/server_upload.tar.gz"
    sftp.putfo(tarball, remote_tar)
    sftp.close()
    print(f"Uploaded {size_kb} KB")

    parent = "/".join(DEPLOY_DIR.rstrip("/").split("/")[:-1])
    run(ssh, f"tar -xzf {remote_tar} -C {parent} --overwrite")
    run(ssh, f"rm {remote_tar}")
    print("Extracted.")

    # 4. Check which container name the existing setup uses
    print("\n--- Checking existing container ---")
    rc, out, _ = run(ssh, "docker inspect gastrocore-server --format '{{.Id}}' 2>/dev/null || echo 'not found'")
    existing_container = out.strip()
    print(f"Existing gastrocore-server: {existing_container[:16] if len(existing_container) > 16 else existing_container}")

    # Find the docker-compose file actually managing the container
    rc, compose_proj, _ = run(ssh, "docker inspect gastrocore-server --format '{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}' 2>/dev/null || echo ''")
    compose_working_dir = compose_proj.strip()
    if compose_working_dir and compose_working_dir != "":
        print(f"Container managed from: {compose_working_dir}")
        effective_dir = compose_working_dir
    else:
        effective_dir = DEPLOY_DIR
        print(f"Using deploy dir: {effective_dir}")

    # 5. Stop old container, rebuild and start
    print(f"\n--- Stopping old container ---")
    # Try without sudo first (tech is in docker group)
    rc, out, err = run(ssh, f"bash -c 'cd {effective_dir} && {dc_cmd} down 2>&1'")
    if rc != 0:
        print(f"Trying with sudo...")
        sudo_run(ssh, f"bash -c 'cd {effective_dir} && {dc_cmd} down 2>&1'")

    print(f"\n--- Building & starting new containers ---")
    print("(This may take 1-3 minutes for Go compilation...)")
    rc, out, err = run(ssh, f"bash -c 'cd {effective_dir} && {dc_cmd} up -d --build 2>&1'")
    if rc != 0:
        print(f"Trying with sudo...")
        rc, out = sudo_run(ssh, f"bash -c 'cd {effective_dir} && {dc_cmd} up -d --build 2>&1'")
        if rc != 0:
            print(f"[ERROR] docker-compose up failed (rc={rc})")

    # 6. Detect port
    print("\n--- Detecting port ---")
    time.sleep(5)
    rc, ports_out, _ = run(ssh, "docker ps --format '{{.Names}} {{.Ports}}'", show=False)
    health_port = 8090  # default from memory
    for line in ports_out.splitlines():
        if "gastrocore" in line and "->" in line:
            m = re.search(r'(?:127\.0\.0\.1:|0\.0\.0\.0:|::)(\d+)->', line)
            if m:
                health_port = int(m.group(1))
                print(f"Detected host port: {health_port}")
                break
    print(f"Using port: {health_port}")

    # 7. Wait for health
    print(f"\n--- Waiting for health at localhost:{health_port}/health ---")
    for attempt in range(1, 25):
        time.sleep(5)
        rc, out, _ = run(ssh, f"curl -sf http://localhost:{health_port}/health", show=False)
        if rc == 0 and out.strip():
            print(f"[OK] Health check passed (attempt {attempt}): {out.strip()}")
            break
        if attempt % 4 == 0:
            print(f"  attempt {attempt}/24 — waiting for container to start...")
    else:
        print(f"\n[ERROR] Health check failed after 2 minutes")
        run(ssh, f"bash -c 'cd {effective_dir} && {dc_cmd} logs --tail=60 api 2>&1'")
        run(ssh, "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")
        ssh.close()
        sys.exit(1)

    # 8. Smoke tests
    print("\n--- Smoke tests ---")
    for path in ["/health", "/demo", "/api/v1/stores", "/api/v1/auth/login"]:
        rc, out, _ = run(ssh, f"curl -sf -o /dev/null -w '%{{http_code}}' http://localhost:{health_port}{path}", show=False)
        status_code = out.strip() if rc == 0 else "ERR"
        body_rc, body, _ = run(ssh, f"curl -sf http://localhost:{health_port}{path} 2>/dev/null | head -c 120", show=False)
        body_preview = body.strip()[:80] if body_rc == 0 else ""
        print(f"  {status_code}  GET {path}  {body_preview}")

    # 9. Check WebSocket
    print("\n--- WebSocket endpoint ---")
    rc, out, _ = run(ssh, f"curl -sf -o /dev/null -w '%{{http_code}}' --http1.1 -H 'Upgrade: websocket' -H 'Connection: Upgrade' http://localhost:{health_port}/ws", show=False)
    print(f"  WS handshake HTTP status: {out.strip() if rc == 0 else 'ERR'}")

    # 10. Final state
    print("\n--- Running containers ---")
    run(ssh, "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")

    ssh.close()

    print("\n=== Deploy complete ===")
    print(f"""
Working URLs
============
Online ordering demo : https://pos.2tech.ch/
Health               : https://pos.2tech.ch/health
                       http://192.168.1.134/health  (LAN via nginx)

API endpoints:
  POST https://pos.2tech.ch/api/v1/auth/register
  POST https://pos.2tech.ch/api/v1/auth/login
  POST https://pos.2tech.ch/api/v1/auth/pin-login
  POST https://pos.2tech.ch/api/v1/auth/pair-device
  POST https://pos.2tech.ch/api/v1/auth/refresh
  GET  https://pos.2tech.ch/api/v1/stores
  GET  https://pos.2tech.ch/api/v1/menu/categories
  GET  https://pos.2tech.ch/demo

WebSocket:
  wss://pos.2tech.ch/ws

VPS direct (port {health_port}):
  http://localhost:{health_port}/health
  ws://localhost:{health_port}/ws
""")


if __name__ == "__main__":
    main()
